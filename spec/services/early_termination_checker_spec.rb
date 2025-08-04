# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSync::EarlyTerminationChecker do
  let(:repository) { "storyblok/storyblok" }
  let(:checker) { described_class.new(repository) }
  let(:owner) { "storyblok" }
  let(:repo) { "storyblok" }

  before do
    # Clean up any existing data
    GithubIssue.destroy_all
    GithubUser.destroy_all
  end

  describe "#initialize" do
    it "sets the repository" do
      expect(checker.instance_variable_get(:@repository)).to eq(repository)
    end

    it "creates timestamp finder instance" do
      timestamp_finder = checker.instance_variable_get(:@timestamp_finder)
      expect(timestamp_finder).to be_a(GithubSync::LastSyncTimestampFinder)
    end
  end

  describe "#can_terminate_early?" do
    context "when no existing data (initial sync)" do
      it "returns false - no early termination for initial sync" do
        issues = create_mock_issues([
          { updated_at: 1.day.ago },
          { updated_at: 2.days.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be false
      end

      it "allows full sync to complete for initial data load" do
        # Even with very old issues, don't terminate early on initial sync
        issues = create_mock_issues([
          { updated_at: 1.year.ago },
          { updated_at: 2.years.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be false
      end
    end

    context "when existing data (incremental sync)" do
      let(:last_sync_time) { 3.days.ago }

      before do
        create_test_issue(issue_updated_at: last_sync_time)
      end

      context "when all issues are newer than last sync" do
        it "returns false - continue pagination" do
          issues = create_mock_issues([
            { updated_at: 1.day.ago },   # newer
            { updated_at: 2.days.ago }   # newer
          ])

          result = checker.can_terminate_early?(issues)
          expect(result).to be false
        end
      end

      context "when some issues are newer than last sync" do
        it "returns false - continue pagination" do
          issues = create_mock_issues([
            { updated_at: 1.day.ago },   # newer
            { updated_at: 4.days.ago }   # older
          ])

          result = checker.can_terminate_early?(issues)
          expect(result).to be false
        end
      end

      context "when all issues are older than last sync" do
        it "returns true - can terminate early" do
          issues = create_mock_issues([
            { updated_at: 4.days.ago },   # older
            { updated_at: 5.days.ago }    # older
          ])

          result = checker.can_terminate_early?(issues)
          expect(result).to be true
        end
      end

      context "when issues exactly match last sync time" do
        it "returns false - equal timestamps are not considered older" do
          issues = create_mock_issues([
            { updated_at: last_sync_time },     # equal (not older, so continue)
            { updated_at: 4.days.ago }          # older
          ])

          result = checker.can_terminate_early?(issues)
          expect(result).to be false
        end
      end

      context "with empty issues array" do
        it "returns true for empty array (all conditions satisfied)" do
          result = checker.can_terminate_early?([])
          expect(result).to be true
        end
      end

      context "with single issue" do
        it "terminates early if single issue is old" do
          issues = create_mock_issues([
            { updated_at: 5.days.ago }
          ])

          result = checker.can_terminate_early?(issues)
          expect(result).to be true
        end

        it "continues if single issue is new" do
          issues = create_mock_issues([
            { updated_at: 1.day.ago }
          ])

          result = checker.can_terminate_early?(issues)
          expect(result).to be false
        end
      end
    end

    context "when no last sync found but data exists" do
      before do
        # Create an issue but simulate scenario where last sync isn't found
        create_test_issue(issue_updated_at: 2.days.ago)

        timestamp_finder = checker.instance_variable_get(:@timestamp_finder)
        allow(timestamp_finder).to receive(:find_last_synced_at).and_return(nil)
      end

      it "returns false when last sync timestamp is nil" do
        issues = create_mock_issues([
          { updated_at: 1.day.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be false
      end
    end
  end

  describe "edge cases and error handling" do
    context "with malformed issue objects" do
      let(:last_sync_time) { 2.days.ago }

      before do
        create_test_issue(issue_updated_at: last_sync_time)
      end

      it "handles issues with nil updated_at" do
        issues = [
          double("issue", updated_at: nil),
          double("issue", updated_at: 5.days.ago)
        ]

        # This will raise an error when comparing nil to Time
        expect { checker.can_terminate_early?(issues) }.to raise_error(NoMethodError)
      end

      it "handles issues with invalid timestamps" do
        issues = [
          double("issue", updated_at: "invalid"),
          double("issue", updated_at: 5.days.ago)
        ]

        expect { checker.can_terminate_early?(issues) }.to raise_error
      end
    end

    context "with different time zones" do
      let(:last_sync_time) { Time.parse("2024-01-15 10:00:00 UTC") }

      before do
        create_test_issue(issue_updated_at: last_sync_time)
      end

      it "handles UTC timestamps correctly" do
        issues = create_mock_issues([
          { updated_at: Time.parse("2024-01-14 10:00:00 UTC") } # 1 day older
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be true
      end

      it "handles local time zone timestamps" do
        # Issue timestamp in local time zone but older than UTC last sync
        local_time = Time.parse("2024-01-14 05:00:00 EST") # converts to UTC
        issues = create_mock_issues([
          { updated_at: local_time }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be true
      end
    end
  end

  describe "integration with sorting strategies" do
    context "with desc sorted issues (incremental sync)" do
      let(:last_sync_time) { 3.days.ago }

      before do
        create_test_issue(issue_updated_at: last_sync_time)
      end

      it "works efficiently with desc sorted issues" do
        # Issues sorted by updated_at desc (newest first)
        issues = create_mock_issues([
          { updated_at: 5.days.ago },   # oldest first in desc order
          { updated_at: 4.days.ago },   # newer but still old
          { updated_at: 4.5.days.ago }  # somewhere in between
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be true
      end

      it "handles mixed age issues in desc order" do
        issues = create_mock_issues([
          { updated_at: 1.day.ago },    # newest (newer than last sync)
          { updated_at: 2.days.ago },   # newer than last sync
          { updated_at: 4.days.ago }    # older than last sync
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be false # mixed ages means continue
      end
    end

    context "with unsorted issues (initial sync)" do
      it "doesn't rely on sorting order for initial sync" do
        # Random order issues - shouldn't matter for initial sync
        issues = create_mock_issues([
          { updated_at: 2.days.ago },
          { updated_at: 5.days.ago },
          { updated_at: 1.day.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be false # initial sync never terminates early
      end
    end
  end

  describe "real-world scenarios" do
    context "Microsoft Terminal repository scenario" do
      let(:last_sync_time) { 1.week.ago }

      before do
        create_test_issue(issue_updated_at: last_sync_time)
      end

      it "handles active repository with recent updates" do
        # Simulate issues from active repository
        issues = create_mock_issues([
          { updated_at: 1.hour.ago },
          { updated_at: 2.hours.ago },
          { updated_at: 1.day.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be false # continue syncing recent updates
      end

      it "terminates early when reaching historical issues" do
        # Simulate reaching old historical issues
        issues = create_mock_issues([
          { updated_at: 2.weeks.ago },
          { updated_at: 3.weeks.ago },
          { updated_at: 1.month.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be true # can stop, all issues are historical
      end
    end

    context "archived repository scenario" do
      let(:last_sync_time) { 6.months.ago }

      before do
        create_test_issue(issue_updated_at: last_sync_time)
      end

      it "quickly terminates for archived repositories" do
        # Simulate archived repository with no recent activity
        issues = create_mock_issues([
          { updated_at: 1.year.ago },
          { updated_at: 2.years.ago }
        ])

        result = checker.can_terminate_early?(issues)
        expect(result).to be true
      end
    end
  end

  private
    def create_mock_issues(issue_data)
      issue_data.map do |data|
        double("issue", data)
      end
    end

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
