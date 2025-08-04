# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSyncCoordinator do
  let(:repository) { "storyblok/storyblok" }
  let(:coordinator) { described_class.new(repository) }

  describe "#initialize" do
    it "sets the repository" do
      expect(coordinator.repository).to eq(repository)
    end
  end

  describe "#queue_sync_jobs" do
    it "queues single issues worker for any sync scenario" do
      total_jobs = coordinator.queue_sync_jobs

      expect(GithubSyncIssuesWorker.jobs.first["args"]).to eq([repository])
    end

    it "handles different repository formats" do
      repos = ["owner/repo", "microsoft/terminal", "facebook/react"]

      repos.each do |repo|
        GithubSyncIssuesWorker.jobs.clear
        coordinator = described_class.new(repo)

        total_jobs = coordinator.queue_sync_jobs

        expect(GithubSyncIssuesWorker.jobs.first["args"]).to eq([repo])
      end
    end
  end

  describe "constants" do
    it "maintains BATCH_SIZE constant for compatibility with workers" do
      expect(GithubSyncCoordinator::BATCH_SIZE).to eq(5_000)
    end
  end

  describe "integration with issues worker" do
    it "queues job that can be processed by issues worker" do
      coordinator.queue_sync_jobs

      job_args = GithubSyncIssuesWorker.jobs.first["args"]
      worker = GithubSyncIssuesWorker.new

      # Verify the worker can accept the arguments
      expect { worker.perform(*job_args) }.not_to raise_error
    end
  end
end
