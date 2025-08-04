# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe GithubSync::IssuePersister do
  let(:repository) { "storyblok/storyblok" }
  let(:persister) { described_class.new(repository) }
  let(:user_processor) { instance_double(GithubSync::UserProcessor) }
  let(:issue_builder) { instance_double(GithubSync::IssueBuilder) }

  before do
    allow(GithubSync::UserProcessor).to receive(:new).and_return(user_processor)
    allow(GithubSync::IssueBuilder).to receive(:new).and_return(issue_builder)
    allow(Rails.cache).to receive(:delete_matched)
    allow(Rails.logger).to receive(:debug)
  end

  describe "#persist" do
    let(:user1) { OpenStruct.new(id: 12345) }
    let(:user2) { OpenStruct.new(id: 67890) }
    let(:issue1) do
      OpenStruct.new(
        number: 1,
        user: user1,
        updated_at: Time.new(2025, 7, 1, 12, 0, 0)
      )
    end
    let(:issue2) do
      OpenStruct.new(
        number: 2,
        user: user2,
        updated_at: Time.new(2025, 7, 2, 12, 0, 0)
      )
    end
    let(:issues) { [issue1, issue2] }
    let(:user_id_map) { { 12345 => 1, 67890 => 2 } }
    let(:issue_records) do
      [
        {
          owner_name: "storyblok",
          repository_name: "storyblok",
          issue_number: 1,
          github_user_id: 1,
          state: "open",
          title: "Issue 1",
          body: "Body 1",
          issue_created_at: Time.new(2025, 7, 1, 10, 0, 0),
          issue_updated_at: Time.new(2025, 7, 1, 12, 0, 0),
          created_at: Time.current,
          updated_at: Time.current
        },
        {
          owner_name: "storyblok",
          repository_name: "storyblok",
          issue_number: 2,
          github_user_id: 2,
          state: "closed",
          title: "Issue 2",
          body: "Body 2",
          issue_created_at: Time.new(2025, 7, 2, 10, 0, 0),
          issue_updated_at: Time.new(2025, 7, 2, 12, 0, 0),
          created_at: Time.current,
          updated_at: Time.current
        }
      ]
    end

    context "with empty issues array" do
      let(:issues) { [] }

      it "returns false immediately" do
        result = persister.persist(issues)
        expect(result).to be false
      end

      it "does not process users or build issue records" do
        persister.persist(issues)

        expect(GithubSync::UserProcessor).not_to have_received(:new)
        expect(GithubSync::IssueBuilder).not_to have_received(:new)
      end
    end

    context "with valid issues that need updating" do
      before do
        # Mock existing issue data - issue 1 exists but is older, issue 2 is new
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation,
            pluck: { 1 => Time.new(2025, 7, 1, 11, 0, 0) } # Issue 1 exists but older
          )
        )
        allow(user_processor).to receive(:process_users).with(issues).and_return(user_id_map)
        allow(issue_builder).to receive(:build_records).with(issues).and_return(issue_records)
        allow(GithubIssue).to receive(:upsert_all)
      end

      it "processes users and gets user ID mapping" do
        persister.persist(issues)

        expect(user_processor).to have_received(:process_users).with(issues)
      end

      it "builds issue records with user ID mapping" do
        persister.persist(issues)

        expect(GithubSync::IssueBuilder).to have_received(:new).with(repository, user_id_map)
        expect(issue_builder).to have_received(:build_records).with(issues)
      end

      it "persists issue records in batches" do
        stub_const("GithubSyncCoordinator::BATCH_SIZE", 1)

        persister.persist(issues)

        expect(GithubIssue).to have_received(:upsert_all).twice
      end

      it "uses correct unique constraint for upserts" do
        persister.persist(issues)

        expect(GithubIssue).to have_received(:upsert_all).with(
          issue_records,
          unique_by: [:owner_name, :repository_name, :issue_number]
        )
      end

      it "does not invalidate cache during persist" do
        persister.persist(issues)

        expect(Rails.cache).not_to have_received(:delete_matched)
      end

      it "returns true on successful persistence" do
        result = persister.persist(issues)
        expect(result).to be true
      end

      it "logs debug messages for batches" do
        stub_const("GithubSyncCoordinator::BATCH_SIZE", 1000)

        persister.persist(issues)

        expect(Rails.logger).to have_received(:debug).with("Persisting batch of 2 issues")
      end
    end

    context "with issues that do not need updating" do
      before do
        # Mock existing issue data - both issues exist and are newer
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation,
            pluck: {
              1 => Time.new(2025, 7, 1, 13, 0, 0), # Newer than issue1.updated_at
              2 => Time.new(2025, 7, 2, 13, 0, 0)  # Newer than issue2.updated_at
            }
          )
        )
      end

      it "returns false when no issues need updating" do
        result = persister.persist(issues)
        expect(result).to be false
      end

      it "does not process users when no updates needed" do
        persister.persist(issues)

        expect(GithubSync::UserProcessor).not_to have_received(:new)
      end

      it "fetches existing issue data correctly" do
        persister.persist(issues)

        expect(GithubIssue).to have_received(:where).with(
          owner_name: "storyblok",
          repository_name: "storyblok",
          issue_number: [1, 2]
        )
      end
    end

    context "with mixed new and existing issues" do
      before do
        # Issue 1 needs update, issue 2 doesn't
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation,
            pluck: {
              1 => Time.new(2025, 7, 1, 11, 0, 0), # Older than issue1.updated_at
              2 => Time.new(2025, 7, 2, 13, 0, 0)  # Newer than issue2.updated_at
            }
          )
        )
        allow(user_processor).to receive(:process_users).and_return(user_id_map)
        allow(issue_builder).to receive(:build_records).and_return([issue_records.first])
        allow(GithubIssue).to receive(:upsert_all)
      end

      it "only processes issues that need updating" do
        persister.persist(issues)

        # Should only process issue1 (the one that needs updating)
        expect(user_processor).to have_received(:process_users).with([issue1])
      end

      it "builds records only for changed issues" do
        persister.persist(issues)

        expect(issue_builder).to have_received(:build_records).with([issue1])
      end

      it "returns true when some issues are processed" do
        result = persister.persist(issues)
        expect(result).to be true
      end
    end

    context "when database transaction fails" do
      before do
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation, pluck: {})
        )
        allow(user_processor).to receive(:process_users).and_return(user_id_map)
        allow(issue_builder).to receive(:build_records).and_return(issue_records)
        allow(GithubIssue).to receive(:upsert_all).and_raise(ActiveRecord::StatementInvalid.new("Database error"))
      end

      it "propagates database errors" do
        expect { persister.persist(issues) }.to raise_error(ActiveRecord::StatementInvalid)
      end

      it "does not invalidate cache on error" do
        begin
          persister.persist(issues)
        rescue ActiveRecord::StatementInvalid
          # Expected error
        end

        expect(Rails.cache).not_to have_received(:delete_matched)
      end
    end

    context "when user processing fails" do
      before do
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation, pluck: {})
        )
        allow(user_processor).to receive(:process_users).and_raise(StandardError.new("User processing failed"))
      end

      it "propagates user processing errors" do
        expect { persister.persist(issues) }.to raise_error(StandardError, "User processing failed")
      end
    end

    context "when issue building fails" do
      before do
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation, pluck: {})
        )
        allow(user_processor).to receive(:process_users).and_return(user_id_map)
        allow(issue_builder).to receive(:build_records).and_raise(StandardError.new("Issue building failed"))
      end

      it "propagates issue building errors" do
        expect { persister.persist(issues) }.to raise_error(StandardError, "Issue building failed")
      end
    end

    context "with large batch sizes" do
      let(:large_issue_set) do
        (1..500).map do |i|
          OpenStruct.new(
            number: i,
            user: OpenStruct.new(id: 12345),
            updated_at: Time.current
          )
        end
      end
      let(:large_issue_records) do
        (1..500).map do |i|
          {
            owner_name: "storyblok",
            repository_name: "storyblok",
            issue_number: i,
            github_user_id: 1,
            state: "open",
            title: "Issue #{i}",
            body: "Body #{i}",
            issue_created_at: Time.current,
            issue_updated_at: Time.current,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      end

      before do
        stub_const("GithubSyncCoordinator::BATCH_SIZE", 100)
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation, pluck: {})
        )
        allow(user_processor).to receive(:process_users).and_return({ 12345 => 1 })
        allow(issue_builder).to receive(:build_records).and_return(large_issue_records)
        allow(GithubIssue).to receive(:upsert_all)
      end

      it "processes records in correct batch sizes" do
        persister.persist(large_issue_set)

        # Should be called 5 times (500 records / 100 batch size)
        expect(GithubIssue).to have_received(:upsert_all).exactly(5).times
      end

      it "logs debug message for each batch" do
        persister.persist(large_issue_set)

        expect(Rails.logger).to have_received(:debug).with("Persisting batch of 100 issues").exactly(5).times
      end
    end

    context "with complex repository names containing special characters" do
      let(:complex_repository) { "my-org/project.name-with_special" }
      let(:complex_persister) { described_class.new(complex_repository) }

      before do
        allow(GithubIssue).to receive(:where).and_return(
          instance_double(ActiveRecord::Relation, pluck: {})
        )
      end

      it "handles complex repository names correctly" do
        allow(user_processor).to receive(:process_users).and_return({})
        allow(issue_builder).to receive(:build_records).and_return([])

        complex_persister.persist(issues)

        # Cache invalidation no longer happens in persister
        expect(Rails.cache).not_to have_received(:delete_matched)
      end
    end
  end
end
