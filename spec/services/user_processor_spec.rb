# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe GithubSync::UserProcessor do
  before do
    @processor = described_class.new
    @bulk_processor = class_double(GithubUsers::BulkProcessor)
    stub_const("GithubUsers::BulkProcessor", @bulk_processor)
    allow(@bulk_processor).to receive(:process).and_return({ 12345 => 1, 67890 => 2 })
    allow(Time).to receive(:current).and_return(Time.new(2025, 8, 1, 12, 0, 0))
  end

  describe "#process_users" do
    before do
      @user1_data = OpenStruct.new(id: 12345, login: "alice", avatar_url: "https://avatar1.com", type: "User", url: "https://api.github.com/users/alice")
      @user2_data = OpenStruct.new(id: 67890, login: "bob", avatar_url: "https://avatar2.com", type: "User", url: "https://api.github.com/users/bob")
      @issue1 = OpenStruct.new(number: 1, user: @user1_data)
      @issue2 = OpenStruct.new(number: 2, user: @user2_data)
      @issue3 = OpenStruct.new(number: 3, user: @user1_data) # Duplicate user
      @issues = [@issue1, @issue2, @issue3]
    end

    context "with valid issues containing users" do
      it "extracts unique users from issues" do
        # Explicit action: process users
        @processor.process_users(@issues)

        expected_records = [
          {
            github_id: 12345,
            username: "alice",
            avatar_url: "https://avatar1.com",
            account_type: "User",
            api_url: "https://api.github.com/users/alice",
            created_at: Time.new(2025, 8, 1, 12, 0, 0),
            updated_at: Time.new(2025, 8, 1, 12, 0, 0)
          },
          {
            github_id: 67890,
            username: "bob",
            avatar_url: "https://avatar2.com",
            account_type: "User",
            api_url: "https://api.github.com/users/bob",
            created_at: Time.new(2025, 8, 1, 12, 0, 0),
            updated_at: Time.new(2025, 8, 1, 12, 0, 0)
          }
        ]

        expect(@bulk_processor).to have_received(:process).with(expected_records)
      end

      it "returns the user ID mapping from bulk processor" do
        result = @processor.process_users(@issues)
        expect(result).to eq({ 12345 => 1, 67890 => 2 })
      end
    end

    context "with empty issues array" do
      before do
        # Explicit setup: empty issues array
        @empty_issues = []
      end

      it "returns empty hash" do
        # Explicit action: process empty issues
        result = @processor.process_users(@empty_issues)
        expect(result).to eq({})
      end

      it "does not call bulk processor" do
        # Explicit action: process empty issues
        @processor.process_users(@empty_issues)
        expect(@bulk_processor).not_to have_received(:process)
      end
    end

    context "with issues containing nil users" do
      before do
        # Explicit setup: create issue with nil user
        @issue_without_user = OpenStruct.new(number: 1, user: nil)
        @issues_with_nil = [@issue1, @issue_without_user, @issue2]
      end

      it "filters out nil users and processes valid ones" do
        # Explicit action: process issues with nil users
        result = @processor.process_users(@issues_with_nil)

        expect(@bulk_processor).to have_received(:process) do |user_records|
          expect(user_records.length).to eq(2)
          expect(user_records.map { |u| u[:github_id] }).to contain_exactly(12345, 67890)
        end

        expect(result).to eq({ 12345 => 1, 67890 => 2 })
      end
    end

    context "with only nil users" do
      before do
        # Explicit setup: create issues with only nil users
        @issues_only_nil = [OpenStruct.new(number: 1, user: nil), OpenStruct.new(number: 2, user: nil)]
      end

      it "returns empty hash" do
        # Explicit action: process issues with only nil users
        result = @processor.process_users(@issues_only_nil)
        expect(result).to eq({})
      end

      it "does not call bulk processor" do
        # Explicit action: process issues with only nil users
        @processor.process_users(@issues_only_nil)
        expect(@bulk_processor).not_to have_received(:process)
      end
    end

    context "with users containing null bytes in strings" do
      before do
        # Explicit setup: create user with null bytes in strings
        @user_with_nulls = OpenStruct.new(id: 99999, login: "test\0user", avatar_url: "https://avatar\0.com",
type: "User\0", url: "https://api\0.com")
        @issue_with_nulls = OpenStruct.new(number: 1, user: @user_with_nulls)
        @issues_with_nulls = [@issue_with_nulls]
      end

      it "sanitizes strings by removing null bytes" do
        # Explicit action: process issues with null bytes
        @processor.process_users(@issues_with_nulls)

        expect(@bulk_processor).to have_received(:process) do |user_records|
          user_record = user_records.first
          expect(user_record[:username]).to eq("testuser")
          expect(user_record[:avatar_url]).to eq("https://avatar.com")
          expect(user_record[:account_type]).to eq("User")
          expect(user_record[:api_url]).to eq("https://api.com")
        end
      end
    end

    context "with users containing nil string values" do
      before do
        # Explicit setup: create user with nil string values
        @user_with_nils = OpenStruct.new(id: 88888, login: nil, avatar_url: nil, type: nil, url: nil)
        @issue_with_nils = OpenStruct.new(number: 1, user: @user_with_nils)
        @issues_with_nils = [@issue_with_nils]
      end

      it "handles nil string values gracefully" do
        # Explicit action: process issues with nil string values
        @processor.process_users(@issues_with_nils)

        expect(@bulk_processor).to have_received(:process) do |user_records|
          user_record = user_records.first
          expect(user_record[:username]).to be_nil
          expect(user_record[:avatar_url]).to be_nil
          expect(user_record[:account_type]).to be_nil
          expect(user_record[:api_url]).to be_nil
        end
      end
    end

    context "when bulk processor raises an error" do
      before do
        # Explicit setup: configure bulk processor to raise error
        allow(@bulk_processor).to receive(:process).and_raise(StandardError.new("Database error"))
      end

      it "propagates the error" do
        # Explicit action: expect error to be raised
        expect { @processor.process_users(@issues) }.to raise_error(StandardError, "Database error")
      end
    end
  end
end
