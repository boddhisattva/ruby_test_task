# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSync::IssueBuilder do
  let(:repository) { "storyblok/storyblok" }
  let(:user_id_map) { { 12345 => 1, 67890 => 2, 99999 => 3 } }
  let(:builder) { described_class.new(repository, user_id_map) }

  describe "#build_records" do
    let(:user1) { OpenStruct.new(id: 12345, login: "alice") }
    let(:user2) { OpenStruct.new(id: 67890, login: "bob") }
    let(:issue1_data) do
      OpenStruct.new(
        number: 1,
        user: user1,
        state: "open",
        title: "Bug in authentication",
        body: "Users cannot log in",
        created_at: Time.new(2025, 7, 1, 10, 0, 0),
        updated_at: Time.new(2025, 7, 1, 11, 0, 0)
      )
    end
    let(:issue2_data) do
      OpenStruct.new(
        number: 2,
        user: user2,
        state: "closed",
        title: "Feature request",
        body: "Add dark mode",
        created_at: Time.new(2025, 7, 2, 10, 0, 0),
        updated_at: Time.new(2025, 7, 2, 11, 0, 0)
      )
    end

    before do
      allow(Time).to receive(:current).and_return(Time.new(2025, 8, 1, 12, 0, 0))
      allow(Rails.logger).to receive(:warn)
      allow(Rails.logger).to receive(:error)
    end

    context "with valid issues" do
      let(:issues) { [issue1_data, issue2_data] }

      it "builds issue records for all valid issues" do
        result = builder.build_records(issues)

        expect(result).to contain_exactly(
          {
            owner_name: "storyblok",
            repository_name: "storyblok",
            issue_number: 1,
            github_user_id: 1,
            state: "open",
            title: "Bug in authentication",
            body: "Users cannot log in",
            issue_created_at: Time.new(2025, 7, 1, 10, 0, 0),
            issue_updated_at: Time.new(2025, 7, 1, 11, 0, 0),
            created_at: Time.new(2025, 8, 1, 12, 0, 0),
            updated_at: Time.new(2025, 8, 1, 12, 0, 0)
          },
          {
            owner_name: "storyblok",
            repository_name: "storyblok",
            issue_number: 2,
            github_user_id: 2,
            state: "closed",
            title: "Feature request",
            body: "Add dark mode",
            issue_created_at: Time.new(2025, 7, 2, 10, 0, 0),
            issue_updated_at: Time.new(2025, 7, 2, 11, 0, 0),
            created_at: Time.new(2025, 8, 1, 12, 0, 0),
            updated_at: Time.new(2025, 8, 1, 12, 0, 0)
          }
        )
      end

      it "maps GitHub user IDs correctly" do
        result = builder.build_records(issues)

        expect(result[0][:github_user_id]).to eq(1) # user1 maps to ID 1
        expect(result[1][:github_user_id]).to eq(2) # user2 maps to ID 2
      end
    end

    context "with issues containing nil users" do
      let(:issue_without_user) { OpenStruct.new(number: 3, user: nil, state: "open", title: "Test") }
      let(:issues) { [issue1_data, issue_without_user] }

      it "skips issues with nil users" do
        result = builder.build_records(issues)

        expect(result.length).to eq(1)
        expect(result[0][:issue_number]).to eq(1)
      end

      it "logs warning for skipped issues" do
        builder.build_records(issues)

        expect(Rails.logger).to have_received(:warn).with("Skipping issue 3 - no user")
      end
    end

    context "with users not in user_id_map" do
      let(:unknown_user) { OpenStruct.new(id: 88888, login: "unknown") }
      let(:issue_with_unknown_user) do
        OpenStruct.new(
          number: 4,
          user: unknown_user,
          state: "open",
          title: "Unknown user issue"
        )
      end
      let(:issues) { [issue1_data, issue_with_unknown_user] }

      it "skips issues with unmapped users" do
        result = builder.build_records(issues)

        expect(result.length).to eq(1)
        expect(result[0][:issue_number]).to eq(1)
      end

      it "logs error for failed user resolution" do
        builder.build_records(issues)

        expect(Rails.logger).to have_received(:error).with("Failed to resolve user 88888")
      end
    end

    context "with issues containing null bytes in strings" do
      let(:issue_with_nulls) do
        OpenStruct.new(
          number: 5,
          user: user1,
          state: "open",
          title: "Bug with\0null bytes",
          body: "Description\0contains nulls",
          created_at: Time.new(2025, 7, 1, 10, 0, 0),
          updated_at: Time.new(2025, 7, 1, 11, 0, 0)
        )
      end
      let(:issues) { [issue_with_nulls] }

      it "sanitizes strings by removing null bytes" do
        result = builder.build_records(issues)

        expect(result[0][:title]).to eq("Bug withnull bytes")
        expect(result[0][:body]).to eq("Descriptioncontains nulls")
      end
    end

    context "with issues containing nil string values" do
      let(:issue_with_nils) do
        OpenStruct.new(
          number: 6,
          user: user1,
          state: "open",
          title: nil,
          body: nil,
          created_at: Time.new(2025, 7, 1, 10, 0, 0),
          updated_at: Time.new(2025, 7, 1, 11, 0, 0)
        )
      end
      let(:issues) { [issue_with_nils] }

      it "handles nil string values gracefully" do
        result = builder.build_records(issues)

        expect(result[0][:title]).to be_nil
        expect(result[0][:body]).to be_nil
      end
    end

    context "with empty issues array" do
      let(:issues) { [] }

      it "returns empty array" do
        result = builder.build_records(issues)
        expect(result).to eq([])
      end
    end

    context "with mixed valid and invalid issues" do
      let(:invalid_issue1) { OpenStruct.new(number: 7, user: nil) }
      let(:invalid_issue2) { OpenStruct.new(number: 8, user: OpenStruct.new(id: 88888)) } # User not in map
      let(:issues) { [issue1_data, invalid_issue1, issue2_data, invalid_issue2] }

      it "returns only valid issue records" do
        result = builder.build_records(issues)

        expect(result.length).to eq(2)
        expect(result.map { |r| r[:issue_number] }).to contain_exactly(1, 2)
      end

      it "logs appropriate messages for each invalid issue" do
        builder.build_records(issues)

        expect(Rails.logger).to have_received(:warn).with("Skipping issue 7 - no user")
        expect(Rails.logger).to have_received(:error).with("Failed to resolve user 88888")
      end
    end

    context "with complex repository names" do
      let(:complex_repository) { "my-org/my-project-name" }
      let(:complex_builder) { described_class.new(complex_repository, user_id_map) }

      it "parses complex repository names correctly" do
        result = complex_builder.build_records([issue1_data])

        expect(result[0][:owner_name]).to eq("my-org")
        expect(result[0][:repository_name]).to eq("my-project-name")
      end
    end

    context "with different issue states" do
      let(:draft_issue) do
        OpenStruct.new(
          number: 9,
          user: user1,
          state: "draft",
          title: "Draft issue",
          body: "Work in progress",
          created_at: Time.current,
          updated_at: Time.current
        )
      end
      let(:issues) { [draft_issue] }

      it "preserves all issue states" do
        result = builder.build_records(issues)

        expect(result[0][:state]).to eq("draft")
      end
    end

    context "edge case: repository with single name" do
      let(:single_name_repo) { "standalone-repo" }
      let(:single_name_builder) { described_class.new(single_name_repo, user_id_map) }

      it "handles repositories without owner correctly" do
        # This would be unusual but the code should handle it
        result = single_name_builder.build_records([issue1_data])

        expect(result[0][:owner_name]).to eq("standalone-repo")
        expect(result[0][:repository_name]).to be_nil
      end
    end
  end
end
