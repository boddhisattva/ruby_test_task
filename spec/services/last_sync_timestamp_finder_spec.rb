# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSync::LastSyncTimestampFinder do
  let(:repository) { "storyblok/storyblok" }
  let(:finder) { described_class.new(repository) }
  let(:owner) { "storyblok" }
  let(:repo) { "storyblok" }

  before do
    # Clean up any existing data
    GithubIssue.destroy_all
    GithubUser.destroy_all
  end

  describe "#should_filter_by_time?" do
    context "when no issues exist for repository" do
      it "returns false" do
        expect(finder.should_filter_by_time?).to be false
      end
    end

    context "when issues exist for repository" do
      before do
        create_test_issue(issue_updated_at: 2.days.ago)
      end

      it "returns true" do
        expect(finder.should_filter_by_time?).to be true
      end
    end

    context "when issues exist for different repository" do
      before do
        create_test_issue(
          owner_name: "different",
          repository_name: "repo",
          issue_updated_at: 1.day.ago
        )
      end

      it "returns false (only looks at specified repository)" do
        expect(finder.should_filter_by_time?).to be false
      end
    end
  end

  describe "#find_last_synced_at" do
    context "when no issues exist" do
      it "returns nil" do
        expect(finder.find_last_synced_at).to be_nil
      end
    end

    context "when single issue exists" do
      let(:sync_time) { 3.days.ago }

      before do
        create_test_issue(issue_updated_at: sync_time)
      end

      it "returns the issue's updated_at timestamp" do
        result = finder.find_last_synced_at
        expect(result).to be_within(1.second).of(sync_time)
      end
    end

    context "when multiple issues exist" do
      let(:oldest_time) { 5.days.ago }
      let(:middle_time) { 3.days.ago }
      let(:newest_time) { 1.day.ago }

      before do
        create_test_issue(issue_number: 1, issue_updated_at: oldest_time)
        create_test_issue(issue_number: 2, issue_updated_at: newest_time)
        create_test_issue(issue_number: 3, issue_updated_at: middle_time)
      end

      it "returns the most recent issue_updated_at timestamp" do
        result = finder.find_last_synced_at
        expect(result).to be_within(1.second).of(newest_time)
      end

      it "ignores issue_created_at and only looks at issue_updated_at" do
        # Create issue with newer created_at but older updated_at
        create_test_issue(
          issue_number: 4,
          issue_created_at: Time.current, # newest created
          issue_updated_at: 10.days.ago   # oldest updated
        )

        result = finder.find_last_synced_at
        expect(result).to be_within(1.second).of(newest_time) # still the newest updated
      end
    end

    context "when issues exist for multiple repositories" do
      let(:our_repo_time) { 2.days.ago }
      let(:other_repo_time) { 1.hour.ago }

      before do
        # Issue in our repository
        create_test_issue(
          owner_name: owner,
          repository_name: repo,
          issue_updated_at: our_repo_time
        )

        # Issue in different repository (newer)
        create_test_issue(
          owner_name: "different",
          repository_name: "repo",
          issue_updated_at: other_repo_time
        )
      end

      it "only considers issues from specified repository" do
        result = finder.find_last_synced_at
        expect(result).to be_within(1.second).of(our_repo_time)
        expect(result).not_to be_within(1.hour).of(other_repo_time)
      end
    end
  end

  describe "edge cases" do
    context "with nil repository" do
      let(:finder) { described_class.new(nil) }

      it "handles nil repository gracefully" do
        # The by_repository scope will handle nil repository
        expect { finder.should_filter_by_time? }.not_to raise_error
        expect { finder.find_last_synced_at }.not_to raise_error

        expect(finder.should_filter_by_time?).to be false
        expect(finder.find_last_synced_at).to be_nil
      end
    end

    context "with empty repository string" do
      let(:finder) { described_class.new("") }

      it "handles empty repository string" do
        expect { finder.should_filter_by_time? }.not_to raise_error
        expect { finder.find_last_synced_at }.not_to raise_error
      end
    end

    context "with malformed repository string" do
      let(:finder) { described_class.new("invalid-format") }

      it "handles malformed repository string" do
        expect { finder.should_filter_by_time? }.not_to raise_error
        expect { finder.find_last_synced_at }.not_to raise_error
      end
    end

    context "with repository containing special characters" do
      let(:special_repo) { "owner/repo-with-dashes_and_underscores.dots" }
      let(:finder) { described_class.new(special_repo) }

      it "handles special characters in repository name" do
        expect { finder.should_filter_by_time? }.not_to raise_error
        expect { finder.find_last_synced_at }.not_to raise_error
      end
    end
  end

  describe "integration with incremental sync" do
    context "first sync scenario" do
      it "indicates no time filtering needed" do
        expect(finder.should_filter_by_time?).to be false
        expect(finder.find_last_synced_at).to be_nil
      end
    end

    context "subsequent sync scenario" do
      let(:last_sync) { 2.hours.ago }

      before do
        create_test_issue(issue_updated_at: last_sync)
      end

      it "provides last sync timestamp for incremental sync" do
        expect(finder.should_filter_by_time?).to be true

        result = finder.find_last_synced_at
        expect(result).to be_within(1.second).of(last_sync)
      end

      it "enables building since parameter for GitHub API" do
        last_sync_time = finder.find_last_synced_at
        since_param = (last_sync_time - 1.minute).iso8601

        expect(since_param).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
      end
    end
  end

  describe "different repository formats" do
    it "works with various repository name formats" do
      repositories = [
        "owner/repo",
        "microsoft/terminal",
        "facebook/react",
        "storyblok/storyblok-js-client",
        "organization-name/repository-name"
      ]

      repositories.each do |repo|
        finder = described_class.new(repo)

        expect { finder.should_filter_by_time? }.not_to raise_error
        expect { finder.find_last_synced_at }.not_to raise_error
      end
    end
  end

  describe "timestamp precision" do
    it "maintains microsecond precision" do
      precise_time = Time.parse("2024-01-15 10:30:45.123456 UTC")
      create_test_issue(issue_updated_at: precise_time)

      result = finder.find_last_synced_at
      expect(result.usec).to eq(precise_time.usec)
    end
  end

  private
    def create_test_issue(attributes = {})
      # Create a test user first
      user = GithubUser.create!(
        github_id: attributes[:user_id] || rand(1000..9999),
        username: attributes[:username] || "testuser#{rand(1000)}",
        avatar_url: "https://github.com/avatar",
        account_type: "User",
        api_url: "https://api.github.com/users/testuser"
      )

      default_attributes = {
        owner_name: owner,
        repository_name: repo,
        issue_number: rand(1..9999),
        title: "Test issue",
        state: "open",
        github_user: user,
        issue_created_at: 1.week.ago,
        issue_updated_at: 1.day.ago
      }

      GithubIssue.create!(default_attributes.merge(attributes))
    end
end
