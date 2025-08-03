# frozen_string_literal: true

class GithubSyncCoordinator
  attr_reader :repository

  # Batching to support enterprise scale
  BATCH_SIZE = 5_000

  def initialize(repository)
    @repository = repository
  end

  def queue_sync_jobs
    # TODO: Plan to add incremental sync for updated issues later
    new_issues_jobs = queue_new_issues_sync

    total_jobs = new_issues_jobs
    Rails.logger.info "Queued #{total_jobs} sync jobs for #{repository} (#{new_issues_jobs} for new issues as part of initial sync)"

    total_jobs
  end

  def queue_new_issues_sync
    GithubSyncIssuesWorker.perform_async(repository, "new")
  end
end
