# frozen_string_literal: true

module GithubSync
  class SyncOptionsBuilder
    def initialize(repository, page_number = nil)
      @repository = repository
      @page_number = page_number
      @timestamp_finder = LastSyncTimestampFinder.new(repository)
    end

    def build_options_for_initial_pagination
      if @timestamp_finder.should_filter_by_time?
        # For incremental sync, use filtering options
        incremental_sync_options
      else
        # For initial sync, fetch all issues
        initial_sync_options
      end
    end

    private
      def base_options
        # Determine if this is an initial sync or incremental sync
        if @timestamp_finder.should_filter_by_time?
          incremental_sync_options
        else
          initial_sync_options
        end
      end

      def initial_sync_options
        # For initial sync: fetch ALL issues without any filtering
        {
          state: "all",
          per_page: 100
        }
      end

      def incremental_sync_options
        # For incremental sync: fetch only recently updated issues
        last_sync = @timestamp_finder.find_last_synced_at

        initial_sync_options.merge(
          sort: "updated",
          direction: "desc",
          since: (last_sync - 1.minute).iso8601  # Add 1-minute buffer to handle edge cases
        )
      end
  end
end
