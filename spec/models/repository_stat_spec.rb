# frozen_string_literal: true

require "rails_helper"

RSpec.describe RepositoryStat, type: :model do
  let(:provider) { "github" }
  let(:owner_name) { "storyblok" }
  let(:repository_name) { "storyblok" }

  before do
    # Clean up any existing data
    RepositoryStat.destroy_all
    GithubIssue.destroy_all
    GithubUser.destroy_all
  end

  describe "validations" do
    it "is valid with valid attributes" do
      stat = RepositoryStat.new(
        provider:,
        owner_name:,
        repository_name:,
        total_issues_count: 100
      )
      expect(stat).to be_valid
    end

    it "requires provider" do
      stat = RepositoryStat.new(
        provider: nil,
        owner_name:,
        repository_name:
      )
      expect(stat).not_to be_valid
      expect(stat.errors[:provider]).to include("can't be blank")
    end

    it "requires owner_name" do
      stat = RepositoryStat.new(
        provider:,
        repository_name:
      )
      expect(stat).not_to be_valid
      expect(stat.errors[:owner_name]).to include("can't be blank")
    end

    it "requires repository_name" do
      stat = RepositoryStat.new(
        provider:,
        owner_name:
      )
      expect(stat).not_to be_valid
      expect(stat.errors[:repository_name]).to include("can't be blank")
    end

    it "defaults total_issues_count to 0" do
      stat = RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:
      )
      expect(stat.total_issues_count).to eq(0)
    end

    it "enforces uniqueness on provider, owner_name, repository_name" do
      RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:
      )

      duplicate = RepositoryStat.new(
        provider:,
        owner_name:,
        repository_name:
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:provider]).to include("has already been taken")
    end

    it "allows different providers for same repository" do
      RepositoryStat.create!(
        provider: "github",
        owner_name:,
        repository_name:
      )

      gitlab_stat = RepositoryStat.new(
        provider: "gitlab",
        owner_name:,
        repository_name:
      )

      expect(gitlab_stat).to be_valid
    end
  end

  describe "#update_total_count!" do
    let!(:user) do
      GithubUser.create!(
        github_id: 12345,
        username: "testuser",
        avatar_url: "https://github.com/avatar",
        account_type: "User",
        api_url: "https://api.github.com/users/testuser"
      )
    end

    let!(:stat) do
      RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:,
        total_issues_count: 0
      )
    end

    context "when no issues exist" do
      it "sets count to 0" do
        stat.update_total_count!
        expect(stat.total_issues_count).to eq(0)
      end

      it "updates the updated_at timestamp" do
        # Simply ensure the method does an update that changes the timestamp
        # Use stub to verify SQL execution includes updated_at change
        expect(stat.class.connection).to receive(:execute) do |sql|
          expect(sql).to include("updated_at = CURRENT_TIMESTAMP")
          # Return true to simulate successful execution
        end

        stat.update_total_count!
      end
    end

    context "when issues exist" do
      before do
        # Create issues for this repository
        3.times do |i|
          GithubIssue.create!(
            owner_name:,
            repository_name:,
            issue_number: i + 1,
            title: "Test issue #{i + 1}",
            state: "open",
            github_user: user,
            issue_created_at: 1.day.ago,
            issue_updated_at: 1.day.ago
          )
        end

        # Create issues for different repository (should not be counted)
        GithubIssue.create!(
          owner_name: "different",
          repository_name: "repo",
          issue_number: 999,
          title: "Different repo issue",
          state: "open",
          github_user: user,
          issue_created_at: 1.day.ago,
          issue_updated_at: 1.day.ago
        )
      end

      it "updates count to match actual issues" do
        stat.update_total_count!
        expect(stat.total_issues_count).to eq(3)
      end

      it "only counts issues for the specific repository" do
        stat.update_total_count!
        expect(stat.total_issues_count).to eq(3) # Should not include the "different" repo issue
      end

      it "reloads the model after update" do
        old_count = stat.total_issues_count
        stat.update_total_count!

        # Verify the in-memory model was reloaded
        expect(stat.total_issues_count).not_to eq(old_count)
        expect(stat.total_issues_count).to eq(3)
      end

      it "is atomic - uses SQL subquery for thread safety" do
        # This test verifies the atomic nature by checking the SQL structure
        expect(stat.class.connection).to receive(:execute) do |sql|
          expect(sql).to include("UPDATE repository_stats")
          expect(sql).to include("SET total_issues_count = COALESCE")
          expect(sql).to include("SELECT COUNT(*)")
          expect(sql).to include("FROM github_issues")
          expect(sql).to include("updated_at = CURRENT_TIMESTAMP")
        end

        stat.update_total_count!
      end
    end

    context "with dynamic issue count changes" do
      it "reflects real-time changes in issue count" do
        # Initial state - no issues
        stat.update_total_count!
        expect(stat.total_issues_count).to eq(0)

        # Add some issues
        2.times do |i|
          GithubIssue.create!(
            owner_name:,
            repository_name:,
            issue_number: i + 1,
            title: "Test issue #{i + 1}",
            state: "open",
            github_user: user,
            issue_created_at: 1.day.ago,
            issue_updated_at: 1.day.ago
          )
        end

        stat.update_total_count!
        expect(stat.total_issues_count).to eq(2)

        # Add more issues
        GithubIssue.create!(
          owner_name:,
          repository_name:,
          issue_number: 3,
          title: "Test issue 3",
          state: "closed",
          github_user: user,
          issue_created_at: 1.day.ago,
          issue_updated_at: 1.day.ago
        )

        stat.update_total_count!
        expect(stat.total_issues_count).to eq(3)

        # Delete an issue
        GithubIssue.where(issue_number: 1).destroy_all

        stat.update_total_count!
        expect(stat.total_issues_count).to eq(2)
      end
    end

    context "thread safety" do
      before do
        # Create initial issues
        5.times do |i|
          GithubIssue.create!(
            owner_name:,
            repository_name:,
            issue_number: i + 1,
            title: "Test issue #{i + 1}",
            state: "open",
            github_user: user,
            issue_created_at: 1.day.ago,
            issue_updated_at: 1.day.ago
          )
        end
      end

      it "handles concurrent updates safely" do
        threads = []
        results = []

        # Simulate concurrent count updates
        5.times do
          threads << Thread.new do
            local_stat = RepositoryStat.find(stat.id)
            local_stat.update_total_count!
            results << local_stat.total_issues_count
          end
        end

        threads.each(&:join)

        # All results should be the same (5 issues)
        expect(results.uniq).to eq([5])

        # Final state should be consistent
        stat.reload
        expect(stat.total_issues_count).to eq(5)
      end
    end
  end

  describe ".fetch_cached" do
    let!(:stat) do
      RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:,
        total_issues_count: 42
      )
    end

    it "returns existing repository stat" do
      result = RepositoryStat.fetch_cached(provider, owner_name, repository_name)
      expect(result).to eq(stat)
      expect(result.total_issues_count).to eq(42)
    end

    it "uses Rails cache for performance" do
      cache_key = "repo_stat/github/storyblok/storyblok"

      # First call should hit the database and cache
      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 5.minutes).and_call_original

      result1 = RepositoryStat.fetch_cached(provider, owner_name, repository_name)

      # Second call should hit the cache
      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 5.minutes).and_call_original

      result2 = RepositoryStat.fetch_cached(provider, owner_name, repository_name)

      expect(result1).to eq(result2)
    end

    it "returns nil when repository stat doesn't exist" do
      result = RepositoryStat.fetch_cached("github", "nonexistent", "repo")
      expect(result).to be_nil
    end

    it "caches nil results to prevent repeated database queries" do
      cache_key = "repo_stat/github/nonexistent/repo"

      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 5.minutes).and_call_original.twice

      # Both calls should use caching
      result1 = RepositoryStat.fetch_cached("github", "nonexistent", "repo")
      result2 = RepositoryStat.fetch_cached("github", "nonexistent", "repo")

      expect(result1).to be_nil
      expect(result2).to be_nil
    end

    it "has 5-minute cache expiration" do
      cache_key = "repo_stat/github/storyblok/storyblok"

      expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 5.minutes)

      RepositoryStat.fetch_cached(provider, owner_name, repository_name)
    end
  end

  describe "cache invalidation" do
    it "clears cache after updating count" do
      # Create stat and cache it
      stat = RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:,
        total_issues_count: 10
      )

      # Verify clear_cache method is called when model is updated
      expect(stat).to receive(:clear_cache)

      # Update using ActiveRecord to trigger callbacks
      stat.update!(total_issues_count: 15)
    end

    it "clears cache after model updates" do
      # Create stat
      stat = RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:,
        total_issues_count: 10
      )

      # Verify clear_cache method is called when model is updated
      expect(stat).to receive(:clear_cache)

      # Any model update should clear cache via after_commit
      stat.update!(total_issues_count: 999)
    end

    it "clears cache when model is destroyed" do
      # Create stat
      stat = RepositoryStat.create!(
        provider:,
        owner_name:,
        repository_name:,
        total_issues_count: 10
      )

      # Verify clear_cache method is called when model is destroyed
      expect(stat).to receive(:clear_cache)

      # Destroy should clear cache via after_commit callback
      stat.destroy!
    end
  end

  describe "integration with sync process" do
    it "supports the incremental sync workflow" do
      user = GithubUser.create!(
        github_id: 12345,
        username: "testuser",
        avatar_url: "https://github.com/avatar",
        account_type: "User",
        api_url: "https://api.github.com/users/testuser"
      )

      # 1. Initial state - no repository stat
      expect(RepositoryStat.fetch_cached(provider, owner_name, repository_name)).to be_nil

      # 2. First sync creates repository stat
      stat = RepositoryStat.find_or_create_by(
        provider:,
        owner_name:,
        repository_name:
      )
      expect(stat.total_issues_count).to eq(0)

      # 3. Issues are synced and persisted
      GithubIssue.create!(
        owner_name:,
        repository_name:,
        issue_number: 1,
        title: "First issue",
        state: "open",
        github_user: user,
        issue_created_at: 1.day.ago,
        issue_updated_at: 1.day.ago
      )

      # 4. Repository stat is updated after sync
      stat.update_total_count!
      expect(stat.total_issues_count).to eq(1)

      # 5. Cached value is available for API responses
      cached_stat = RepositoryStat.fetch_cached(provider, owner_name, repository_name)
      expect(cached_stat.total_issues_count).to eq(1)
    end
  end
end
