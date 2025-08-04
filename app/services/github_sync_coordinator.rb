# frozen_string_literal: true

class GithubSyncCoordinator
  attr_reader :repository

  # Batching to support enterprise scale
  BATCH_SIZE = 5_000

  def initialize(repository)
    @repository = repository
  end

  def queue_sync_jobs
    GithubSyncIssuesWorker.perform_async(repository)
  end
end
