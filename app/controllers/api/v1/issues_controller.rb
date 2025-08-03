# frozen_string_literal: true

module Api
  module V1
    class IssuesController < ApplicationController
      before_action :validate_repository_params

      def index
        retrieve_fresh_issues_from_original_provider_source if issues_data_is_stale?

        result = fetch_issues_from_database
        set_response_headers(result[:total_count])

        render json: serialize_issues(result[:issues])
      end

      private
        def repository
          "#{params[:owner]}/#{params[:repo]}"
        end

        def validate_repository_params
          return if params[:provider].present? && params[:owner].present? && params[:repo].present?

          render json: { error: "provider, owner and repo parameters are required" },
                 status: :bad_request
        end

        def fetch_issues_from_database
          IssuesFetcher.new(repository, filter_params).fetch_from_database
        end

        def filter_params
          params.permit(:status, :provider, :page, :per_page, :owner, :repo).to_h.symbolize_keys
        end

        def retrieve_fresh_issues_from_original_provider_source
          GithubSyncCoordinator.new(repository).queue_sync_jobs
        end

        def issues_data_is_stale?
          last_sync = GithubIssue.by_repository(repository).maximum(:updated_at)
          last_sync.nil? || last_sync < 10.minutes.ago
        end

        def set_response_headers(total_count)
          response.headers["X-Total-Count"] = total_count.to_s
        end

        def serialize_issues(issues)
          IssueSerializer.new(issues).serialize
        end
    end
  end
end
