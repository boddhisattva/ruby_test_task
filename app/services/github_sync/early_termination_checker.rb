# frozen_string_literal: true

module GithubSync
  class EarlyTerminationChecker
    def initialize(repository)
      @repository = repository
      @timestamp_finder = LastSyncTimestampFinder.new(repository)
    end

    def can_terminate_early?(issues)
      return false unless @timestamp_finder.should_filter_by_time?

      last_sync = @timestamp_finder.find_last_synced_at
      return false unless last_sync

      # Early termination only works when we sort by updated_at desc
      # For initial sync (no sorting), we don't terminate early
      # This ensures compatibility with existing VCR cassettes
      issues.all? { |issue| issue.updated_at < last_sync }
    end
  end
end
