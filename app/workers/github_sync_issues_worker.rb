# frozen_string_literal: true

class GithubSyncIssuesWorker
  include Sidekiq::Worker

  sidekiq_options retry: 3, queue: "github_issues"

  def perform(repository, sync_type)
    @repository = repository
    @sync_type = sync_type
    @github_client = GithubSync::GithubClient.new
    @persister = GithubSync::IssuePersister.new(repository)

    Rails.logger.info "[#{repository}] Starting offset-based sync"

    accumulated_issues = []
    total_issues_count = 0
    page = 1
    empty_page_count = 0

    loop do
      # TODO: Remove log statements later
      Rails.logger.info "[#{repository}] Fetching page #{page}"

      issues = fetch_page(page)

      case issues

      when nil
        empty_page_count += 1
        Rails.logger.info "[#{repository}] Page #{page} returned no issues (empty page count: #{empty_page_count})"

        Rails.logger.info "[#{repository}] Total issues fetched: #{total_issues_count}"
        break

      else
        # Got issues successfully
        empty_page_count = 0  # Reset empty page counter

        accumulated_issues.concat(issues)
        total_issues_count += issues.size

        Rails.logger.info "[#{repository}] Page #{page}: fetched #{issues.size} issues (total so far: #{total_issues_count})"

        # Persist batch when we reach around 5000 issues
        if accumulated_issues.size >= GithubSyncCoordinator::BATCH_SIZE
          Rails.logger.info "[#{repository}] Reached batch size of #{GithubSyncCoordinator::BATCH_SIZE} - persisting batch"
          @persister.persist(accumulated_issues)
          accumulated_issues.clear
          Rails.logger.info "[#{repository}] Batch persisted, continuing with next batch"
        end

        # Check if there are more issue related pages to paginate through
        unless @github_client.has_next_page?
          Rails.logger.info "[#{repository}] No next page link found after page #{page}"
          Rails.logger.info "[#{repository}] Total issues fetched: #{total_issues_count}"
          break
        end
      end

      page += 1
    end

    # Persist any remaining issues
    if accumulated_issues.any?
      Rails.logger.info "In sync worker: [#{repository}] Persisting final batch of #{accumulated_issues.size} issues"
      @persister.persist(accumulated_issues)
    end

    Rails.logger.info "[#{repository}] Completed offset-based sync - Total issues: #{total_issues_count}"
  end

  private
    def fetch_page(page)
      options = {
        state: "all",
        per_page: GithubSync::GithubClient::GITHUB_MAX_RESULTS_PER_PAGE,
        page:
      }

      begin
        results = @github_client.fetch_issues(@repository, options)
        reject_pull_requests_type_issues(results)
      rescue StandardError => e
        Rails.logger.error "Failed to fetch page #{page}: #{e.message}"
        raise
      end
    end

    def reject_pull_requests_type_issues(results)
      results.reject(&:pull_request)
    end
end
