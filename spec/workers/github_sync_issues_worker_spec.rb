# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSyncIssuesWorker, type: :worker do
  let(:worker) { described_class.new }
  let(:repository) { "octocat/Hello-World" }
  let(:github_client) { instance_double(GithubSync::GithubClient) }
  let(:options_builder) { instance_double(GithubSync::SyncOptionsBuilder) }
  let(:persister) { instance_double(GithubSync::IssuePersister) }
  let(:early_termination_checker) { instance_double(GithubSync::EarlyTerminationChecker) }
  let(:timestamp_finder) { instance_double(GithubSync::LastSyncTimestampFinder) }

  before do
    allow(GithubSync::GithubClient).to receive(:new).and_return(github_client)
    allow(GithubSync::SyncOptionsBuilder).to receive(:new).with(repository).and_return(options_builder)
    allow(GithubSync::IssuePersister).to receive(:new).with(repository).and_return(persister)
    allow(GithubSync::EarlyTerminationChecker).to receive(:new).with(repository).and_return(early_termination_checker)
    allow(GithubSync::LastSyncTimestampFinder).to receive(:new).with(repository).and_return(timestamp_finder)
    allow(Rails.cache).to receive(:delete_matched)
  end

  describe "#perform" do
    context "when performing initial sync" do
      let(:issues_page1) { build_list(:github_issue, 30) }
      let(:issues_page2) { build_list(:github_issue, 20) }
      let(:options) { { state: "all", sort: "updated", direction: "desc", per_page: 100, page: 1 } }

      before do
        allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(false)
        allow(options_builder).to receive(:build_options_for_initial_pagination).and_return(options)
        allow(github_client).to receive(:fetch_issues).with(repository, options).and_return(issues_page1)
        allow(github_client).to receive(:extract_next_url).and_return("https://api.github.com/repos/octocat/Hello-World/issues?page=2", nil)
        allow(github_client).to receive(:fetch_from_url).with("https://api.github.com/repos/octocat/Hello-World/issues?page=2").and_return(issues_page2)
        allow(persister).to receive(:persist)
      end

      it "syncs all issues across multiple pages" do
        expect(persister).to receive(:persist).with(issues_page1 + issues_page2)
        
        worker.perform(repository)
      end


      it "updates repository stats" do
        owner, repo = repository.split("/")
        repo_stat = instance_double(RepositoryStat, provider: "github", owner_name: owner, repository_name: repo, total_issues_count: 50)
        
        allow(RepositoryStat).to receive(:find_or_create_by).with(
          provider: "github",
          owner_name: owner,
          repository_name: repo
        ).and_return(repo_stat)
        
        expect(repo_stat).to receive(:update_total_count!)
        
        worker.perform(repository)
      end

      it "invalidates cache after sync" do
        expect(Rails.cache).to receive(:delete_matched).with("issues:#{repository}:*")
        
        worker.perform(repository)
      end
    end

    context "when performing incremental sync" do
      let(:new_issues) { build_list(:github_issue, 5, updated_at: 1.hour.ago) }
      let(:old_issues) { build_list(:github_issue, 2, updated_at: 2.days.ago) }
      let(:options) { { state: "all", sort: "updated", direction: "desc", per_page: 100, page: 1, since: 1.day.ago.iso8601 } }

      before do
        allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(true)
        allow(options_builder).to receive(:build_options_for_initial_pagination).and_return(options)
        allow(github_client).to receive(:fetch_issues).with(repository, options).and_return(new_issues)
        allow(github_client).to receive(:extract_next_url).and_return("https://api.github.com/repos/octocat/Hello-World/issues?page=2", nil)
        allow(github_client).to receive(:fetch_from_url).and_return(old_issues)
        allow(persister).to receive(:persist)
      end

      context "with early termination enabled" do
        before do
          allow(early_termination_checker).to receive(:can_terminate_early?).with(new_issues).and_return(false)
          allow(early_termination_checker).to receive(:can_terminate_early?).with(old_issues).and_return(true)
        end

        it "terminates early when encountering old issues" do
          expect(persister).to receive(:persist).with(new_issues)
          expect(persister).not_to receive(:persist).with(old_issues)
          
          worker.perform(repository)
        end

      end

      context "without early termination" do
        before do
          allow(early_termination_checker).to receive(:can_terminate_early?).and_return(false)
        end

        it "processes all pages" do
          expect(persister).to receive(:persist).with(new_issues + old_issues)
          
          worker.perform(repository)
        end
      end
    end

    context "when handling batch persistence" do
      let(:large_batch) { build_list(:github_issue, 150) }
      let(:options) { { state: "all", sort: "updated", direction: "desc", per_page: 100, page: 1 } }

      before do
        allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(false)
        allow(options_builder).to receive(:build_options_for_initial_pagination).and_return(options)
        allow(github_client).to receive(:fetch_issues).with(repository, options).and_return(large_batch[0..99])
        allow(github_client).to receive(:extract_next_url).and_return("https://api.github.com/repos/octocat/Hello-World/issues?page=2", nil)
        allow(github_client).to receive(:fetch_from_url).and_return(large_batch[100..149])
        allow(persister).to receive(:persist)
        stub_const("GithubSyncCoordinator::BATCH_SIZE", 100)
      end

      it "persists issues in batches when batch size is reached" do
        expect(persister).to receive(:persist).with(large_batch[0..99]).ordered
        expect(persister).to receive(:persist).with(large_batch[100..149]).ordered
        
        worker.perform(repository)
      end
    end

    context "when handling empty repository" do
      let(:options) { { state: "all", sort: "updated", direction: "desc", per_page: 100, page: 1 } }

      before do
        allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(false)
        allow(options_builder).to receive(:build_options_for_initial_pagination).and_return(options)
        allow(github_client).to receive(:fetch_issues).with(repository, options).and_return([])
        allow(github_client).to receive(:extract_next_url).and_return(nil)
      end

      it "completes successfully with no issues" do
        expect(persister).not_to receive(:persist)
        
        worker.perform(repository)
      end

    end

    context "when handling errors" do
      let(:options) { { state: "all", sort: "updated", direction: "desc", per_page: 100, page: 1 } }
      let(:error_message) { "API rate limit exceeded" }

      before do
        allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(false)
        allow(options_builder).to receive(:build_options_for_initial_pagination).and_return(options)
      end

      context "with network timeout" do
        before do
          allow(github_client).to receive(:fetch_issues).and_raise(Faraday::TimeoutError.new("timeout"))
        end

        it "re-raises timeout error" do
          expect { worker.perform(repository) }.to raise_error(Faraday::TimeoutError)
        end

        it "still performs final operations" do
          owner, repo = repository.split("/")
          repo_stat = instance_double(RepositoryStat, total_issues_count: 0)
          allow(RepositoryStat).to receive(:find_or_create_by).with(
            provider: "github",
            owner_name: owner,
            repository_name: repo
          ).and_return(repo_stat)
          allow(repo_stat).to receive(:update_total_count!)
          
          expect(Rails.cache).to receive(:delete_matched).with("issues:#{repository}:*")
          
          expect { worker.perform(repository) }.to raise_error(Faraday::TimeoutError)
        end
      end

      context "with general error" do
        before do
          allow(github_client).to receive(:fetch_issues).and_raise(StandardError.new(error_message))
        end

        it "re-raises general error" do
          expect { worker.perform(repository) }.to raise_error(StandardError)
        end
      end

      context "with error in final operations" do
        let(:issues) { build_list(:github_issue, 5) }

        before do
          allow(github_client).to receive(:fetch_issues).and_return(issues)
          allow(github_client).to receive(:extract_next_url).and_return(nil)
          allow(persister).to receive(:persist)
          allow(RepositoryStat).to receive(:find_or_create_by).and_raise(StandardError.new("DB error"))
        end

        it "doesn't re-raise error from final operations to avoid masking original error" do
          expect { worker.perform(repository) }.not_to raise_error
        end
      end
    end

    context "when handling pagination edge cases" do
      let(:options) { { state: "all", sort: "updated", direction: "desc", per_page: 100, page: 1 } }

      before do
        allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(false)
        allow(options_builder).to receive(:build_options_for_initial_pagination).and_return(options)
      end

      context "with nil response from API" do
        before do
          allow(github_client).to receive(:fetch_issues).and_return(nil)
          allow(github_client).to receive(:extract_next_url).and_return(nil)
        end

        it "handles nil response gracefully" do
          expect(persister).not_to receive(:persist)
          expect { worker.perform(repository) }.not_to raise_error
        end
      end

      context "with empty page in middle of pagination" do
        let(:issues_page1) { build_list(:github_issue, 30) }
        let(:issues_page3) { build_list(:github_issue, 10) }

        before do
          allow(github_client).to receive(:fetch_issues).and_return(issues_page1)
          allow(github_client).to receive(:extract_next_url).and_return(
            "https://api.github.com/repos/octocat/Hello-World/issues?page=2",
            "https://api.github.com/repos/octocat/Hello-World/issues?page=3",
            nil
          )
          allow(github_client).to receive(:fetch_from_url)
            .with("https://api.github.com/repos/octocat/Hello-World/issues?page=2")
            .and_return([])
          allow(github_client).to receive(:fetch_from_url)
            .with("https://api.github.com/repos/octocat/Hello-World/issues?page=3")
            .and_return(issues_page3)
          allow(persister).to receive(:persist)
        end

        it "terminates on empty page" do
          expect(persister).to receive(:persist).with(issues_page1)
          expect(persister).not_to receive(:persist).with(issues_page3)
          
          worker.perform(repository)
        end
      end
    end
  end

  describe "Sidekiq configuration" do
    it "uses the correct queue" do
      expect(described_class.sidekiq_options["queue"]).to eq("github_issues")
    end

    it "has correct retry configuration" do
      expect(described_class.sidekiq_options["retry"]).to eq(3)
    end
  end
end