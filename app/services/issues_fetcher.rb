# frozen_string_literal: true

class IssuesFetcher
  include Pagy::Backend

  attr_reader :repository, :state, :page, :per_page, :cv

  def initialize(repository, params = {})
    @repository = repository
    # Support both '' and 'state' parameters for backward compatibility
    @state = params[:state] || "open"
    @page = params[:page] || 1
    @per_page = params[:per_page].present? ? params[:per_page].to_i : Pagy::DEFAULT[:limit]
    @cv = params[:cv] || calculate_current_cv
  end

  def fetch
    Rails.cache.fetch(cache_key_with_cv, expires_in: 1.year) do
      fetch_from_database
    end
  end

  private
    def calculate_current_cv
      # Use only issue_updated_at for cache versioning
      # New issues have same created/updated timestamps
      GithubIssue.by_repository(repository).maximum(:issue_updated_at)&.to_i || 0
    end

    def fetch_from_database
      scope = build_query_scope
      pagy, issues = pagy(scope, limit: per_page, page:)

      {
        issues:,
        total_count: pagy.count,
        pagy:,
        per_page:
      }
    end

    def build_query_scope
      GithubIssue.includes(:github_user)
           .by_repository(repository)
           .by_state(state)
           .order(issue_created_at: :desc)
    end

    def cache_key_with_cv
      "issues:#{repository}:#{state}:page_#{page}:per_page_#{per_page}:cv_#{cv}"
    end

    # Required by Pagy::Backend
    def params
      { page: }
    end
end
