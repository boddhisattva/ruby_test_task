# frozen_string_literal: true

module GithubSync
  class GithubClient
    GITHUB_MAX_RESULTS_PER_PAGE = 100

    attr_reader :client

    def initialize
      @client = Octokit::Client.new(
        access_token: Rails.application.credentials.github.api_token
      )
    end

    def fetch_issues(repository, options)
      response = @client.issues(repository, options)
      response.reject(&:pull_request)
    rescue StandardError => e
      Rails.logger.error "Failed to fetch issues: #{e.message}"
      []
    end

    def has_next_page?
      link_header = @client.last_response&.headers&.[]("link")
      link_header&.include?('rel="next"') || false
    end

    def extract_next_url
      response = @client.last_response
      if response && response.rels && response.rels[:next]
        response.rels[:next].href
      end
    rescue StandardError
      nil
    end

    def fetch_from_url(url)
      response = @client.get(url)
      response.reject(&:pull_request)
    rescue StandardError => e
      Rails.logger.error "Failed to fetch from URL #{url}: #{e.message}"
      []
    end
  end
end
