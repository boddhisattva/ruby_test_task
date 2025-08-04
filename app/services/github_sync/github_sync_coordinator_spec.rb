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

    it "logs the queued job" do
      expect(Rails.logger).to receive(:info).with("Queued sync for #{repository}")

      coordinator.queue_sync_jobs
    end
  end

  describe "constants" do
    it "maintains BATCH_SIZE constant for compatibility with workers" do
      expect(GithubSyncCoordinator::BATCH_SIZE).to eq(5_000)
    end
  end
end
