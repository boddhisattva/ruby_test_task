# frozen_string_literal: true

# Handles both initial sync (fetch all issues) and incremental sync (fetch only updated issues)
class GithubSyncIssuesWorker
  GITHUB_PROVIDER = "github"
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: "github_issues"

  def perform(repository)
    initialize_sync_components(repository)
    start_sync
    begin
      sync_with_pagination
    rescue => e
      handle_sync_error(e)
      raise
    ensure
      perform_final_operations
    end
  end

  private
    def initialize_sync_components(repository)
      @repository = repository
      @github_client = GithubSync::GithubClient.new
      @options_builder = GithubSync::SyncOptionsBuilder.new(repository)
      @persister = GithubSync::IssuePersister.new(repository)
      @early_termination_checker = GithubSync::EarlyTerminationChecker.new(repository)
      @timestamp_finder = GithubSync::LastSyncTimestampFinder.new(repository)
    end

    def start_sync
      sync_type = @timestamp_finder.should_filter_by_time? ? "incremental" : "initial"
    end

    def sync_with_pagination
      sync_state = initialize_sync_state

      begin
        process_initial_pagination_request(sync_state)
        process_pagination_chain(sync_state) unless sync_state[:terminated_early]

        finalize_sync(sync_state)
      rescue Faraday::TimeoutError, Net::ReadTimeout => e
        Rails.logger.error "Network timeout for #{@repository}: #{e.message}"
        raise
      rescue StandardError => e
        Rails.logger.error "Sync failed for #{@repository}: #{e.message}"
        raise
      end
    end

    def initialize_sync_state
      {
        accumulated_issues: [],
        total_issues_count: 0,
        page_count: 1,
        found_old_issue: false,
        terminated_early: false,
        is_incremental_sync: @timestamp_finder.should_filter_by_time?
      }
    end

    def process_initial_pagination_request(sync_state)
      options = build_initial_pagination_options
      issues = fetch_initial_issues(options)

      handle_page_result(issues, sync_state)
    end

    def build_initial_pagination_options
      @options_builder.build_options_for_initial_pagination
    end

    def fetch_initial_issues(options)
      @github_client.fetch_issues(@repository, options)
    end

    def handle_page_result(issues, sync_state)
      case issues
      when nil, []
        handle_empty_page(sync_state)
      else
        handle_successful_page(issues, sync_state)
      end
    end

    def handle_empty_page(sync_state)
      sync_state[:terminated_early] = true
    end

    def handle_successful_page(issues, sync_state)
      # Check for early termination in incremental sync
      if should_check_early_termination?(sync_state) && @early_termination_checker.can_terminate_early?(issues)
        handle_early_termination(sync_state)
      else
        accumulate_issues(issues, sync_state)
        persist_batch_if_needed(sync_state)
      end
    end

    def should_check_early_termination?(sync_state)
      sync_state[:is_incremental_sync]
    end

    def handle_early_termination(sync_state)
      sync_state[:terminated_early] = true
      sync_state[:found_old_issue] = true
    end

    def accumulate_issues(issues, sync_state)
      sync_state[:accumulated_issues].concat(issues)
      sync_state[:total_issues_count] += issues.size
    end

    def persist_batch_if_needed(sync_state)
      accumulated_issues = sync_state[:accumulated_issues]

      return unless accumulated_issues.size >= GithubSyncCoordinator::BATCH_SIZE

      @persister.persist(accumulated_issues)
      accumulated_issues.clear
    end

    def process_pagination_chain(sync_state)
      while (next_url = @github_client.extract_next_url)
        if process_next_page(sync_state, next_url)
          break # Early termination
        end

        sync_state[:page_count] += 1
      end
    end

    def process_next_page(sync_state, next_url)
      issues = fetch_next_page(next_url)

      if issues.nil? || issues.empty?
        handle_empty_page(sync_state)
        true # Signal to break the loop
      elsif should_check_early_termination?(sync_state) && @early_termination_checker.can_terminate_early?(issues)
        handle_pagination_chain_termination(sync_state)
        true # Signal to break the loop
      else
        accumulate_issues(issues, sync_state)
        persist_batch_if_needed(sync_state)
        false # Continue processing
      end
    end

    def fetch_next_page(next_url)
      @github_client.fetch_from_url(next_url)
    end

    def handle_pagination_chain_termination(sync_state)
      sync_state[:found_old_issue] = true
    end

    def finalize_sync(sync_state)
      persist_remaining_issues(sync_state[:accumulated_issues])
      determine_completion_status(sync_state)
    end

    def persist_remaining_issues(accumulated_issues)
      return unless accumulated_issues.any?

      @persister.persist(accumulated_issues)
    end

    def determine_completion_status(sync_state)
      if sync_state[:terminated_early] || sync_state[:found_old_issue]
        "with early termination"
      else
        "fully"
      end
    end

    def handle_sync_error(error)
      Rails.logger.error "[#{@repository}] Sync failed: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
    end

    def perform_final_operations
      update_repository_stats_final
      invalidate_cache_final
    rescue => e
      # Log error but don't re-raise to avoid masking original error
      Rails.logger.error "[#{@repository}] Error in final operations: #{e.message}"
    end

    def update_repository_stats_final
      return unless @repository

      owner, repo = @repository.split("/")
      repo_stat = RepositoryStat.find_or_create_by(
        provider: GITHUB_PROVIDER,
        owner_name: owner,
        repository_name: repo
      )

      repo_stat.update_total_count!
    end

    def invalidate_cache_final
      return unless @repository

      # Single, final cache invalidation matching with pattern set in IssuesFetcher
      cache_pattern = "issues:#{@repository}:*"
      Rails.cache.delete_matched(cache_pattern)
    end
end
