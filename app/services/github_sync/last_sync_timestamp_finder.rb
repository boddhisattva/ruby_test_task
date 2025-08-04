# frozen_string_literal: true

module GithubSync
  class LastSyncTimestampFinder
    def initialize(repository)
      @repository = repository
    end

    def find_last_synced_at
      # For incremental sync, find the most recent issue update we have
      GithubIssue
        .by_repository(@repository)
        .maximum(:issue_updated_at)
    end

    def should_filter_by_time?
      # Only filter if we have existing issues
      find_last_synced_at.present?
    end
  end
end
