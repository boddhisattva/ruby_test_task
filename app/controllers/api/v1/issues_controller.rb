# frozen_string_literal: true

module Api
  module V1
    class IssuesController < ApplicationController
      before_action :validate_repository_params

      def index
        serialized_github_issues = nil
        is_empty_repository = false

        # For empty repositories, fetch directly from GitHub API
        if repository_has_no_records?
          github_issues = fetch_initial_issues_from_github
          serialized_github_issues = serialize_github_api_issues(github_issues)
          is_empty_repository = true
        end

        ensure_fresh_data if stale_data?

        cv = calculate_cache_version

        fresh_when(
          etag: "W/\"#{repository}-#{cv}-#{repository_stat_version}\"",
          last_modified: [Time.at(cv).utc, repository_stat&.updated_at].compact.max,
          public: true
        )

        # Return 304 Not Modified if client cache is fresh
        return if request.fresh?(response)

        result = fetch_issues_with_cv(cv)
        set_response_headers_with_stats(is_empty_repository)

        render json: serialized_github_issues || serialize_issues(result[:issues])
      end

      private
        def repository_has_no_records?
          owner, repo = repository.split("/")
          !GithubIssue.exists?(owner_name: owner, repository_name: repo)
        end

        def fetch_initial_issues_from_github
          per_page = params[:per_page].present? ? params[:per_page].to_i : Pagy::DEFAULT[:limit]
          page = params[:page]&.to_i || 1

          client = GithubSync::GithubClient.new
          options = {
            state: map_state_to_github_state,
            sort: "created",
            direction: "desc",
            per_page:,
            page:
          }

          client.fetch_issues(repository, options)
        end

        def serialize_github_api_issues(github_issues)
          github_issues.map do |issue|
            {
              number: issue[:number],
              title: issue[:title],
              body: issue[:body],
              state: issue[:state],
              created_at: issue[:created_at],
              updated_at: issue[:updated_at],
              user: serialize_github_api_user(issue[:user])
            }
          end
        end

        def serialize_github_api_user(user_data)
          return nil unless user_data

          {
            login: user_data[:login],
            avatar_url: user_data[:avatar_url],
            url: user_data[:url],
            type: user_data[:type]
          }
        end

        def map_state_to_github_state
          return "all" if params[:state] == "all"
          params[:state] == "closed" ? "closed" : "open"
        end

        def repository
          "#{params[:owner]}/#{params[:repo]}"
        end

        def validate_repository_params
          return if params[:owner].present? && params[:repo].present?

          render json: { error: "owner and repo parameters are required" },
                 status: :bad_request
        end

        def calculate_cache_version
          # Use GitHub's issue_updated_at for cache versioning
          # This detects both new and updated issues since new issues have same created/updated timestamps
          GithubIssue.by_repository(repository).maximum(:issue_updated_at)&.to_i || 0
        end

        def fetch_issues_with_cv(cv)
          IssuesFetcher.new(repository, filter_params.merge(cv:)).fetch
        end

        def filter_params
          params.permit(:state, :page, :per_page, :owner, :repo).to_h.symbolize_keys
        end

        def ensure_fresh_data
          GithubSyncCoordinator.new(repository).queue_sync_jobs
        end

        def stale_data?
          last_sync = GithubIssue.by_repository(repository).maximum(:updated_at)
          last_sync.nil? || last_sync < 10.minutes.ago
        end

        def set_response_headers_with_stats(is_empty_repository = false)
          total = if is_empty_repository
            Pagy::DEFAULT[:limit]  # Use default limit for empty repositories
          else
            repository_stat&.total_issues_count
          end

          response.headers["X-Total-Count"] = total.to_s
          # 31536000 seconds corresponds to 1 year
          response.headers["Cache-Control"] = "public, max-age=31536000"
        end

        def serialize_issues(issues)
          IssueSerializer.new(issues).serialize
        end

        def repository_stat
          @repository_stat ||= RepositoryStat.fetch_cached(
            params[:provider],
            params[:owner],
            params[:repo]
          )
        end

        def repository_stat_version
          repository_stat&.updated_at&.to_i || 0
        end
    end
  end
end
