# frozen_string_literal: true

class IssuesFetcher
  # Allows using Pagy in a Service class
  include Pagy::Backend

  attr_reader :repository, :status, :page, :per_page

  def initialize(repository, params = {})
    @repository = repository
    @status = params[:status] || "all"
    @page = params[:page] || 1
    @per_page = params[:per_page] || Pagy::DEFAULT[:items]
  end

  def fetch_from_database
    scope = build_query_scope
    pagy, issues = pagy(scope, items: per_page, page:)

    {
      issues:,
      total_count: pagy.count,
      pagy:
    }
  end

  private
    def build_query_scope
      GithubIssue.includes(:github_user)
           .by_repository(repository)
           .by_state(status)
           .order(issue_updated_at: :desc)
    end

    # Required by Pagy::Backend
    def params
      { page: }
    end
end
