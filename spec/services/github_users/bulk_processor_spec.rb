# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubUsers::BulkProcessor do
  describe ".process" do
    let(:user_records) do
      [
        {
          github_id: 12345,
          username: "alice",
          avatar_url: "https://avatars.githubusercontent.com/u/12345",
          account_type: "User",
          api_url: "https://api.github.com/users/alice",
          created_at: Time.current,
          updated_at: Time.current
        },
        {
          github_id: 67890,
          username: "bob",
          avatar_url: "https://avatars.githubusercontent.com/u/67890",
          account_type: "User",
          api_url: "https://api.github.com/users/bob",
          created_at: Time.current,
          updated_at: Time.current
        }
      ]
    end

    context "when user records are empty" do
      it "returns empty hash" do
        result = described_class.process([])
        expect(result).to eq({})
      end
    end

    context "when bulk upsert succeeds" do
      it "returns user id mapping" do
        result = described_class.process(user_records)

        expect(result).to be_a(Hash)
        expect(result.keys).to match_array([12345, 67890])
        expect(result.values).to all(be_a(Integer))
      end

      it "creates users in database" do
        expect { described_class.process(user_records) }
          .to change { GithubUser.count }.by(2)

        alice = GithubUser.find_by(github_id: 12345)
        expect(alice.username).to eq("alice")
        expect(alice.avatar_url).to eq("https://avatars.githubusercontent.com/u/12345")
      end
    end

    context "when updating existing users" do
      before do
        create(:github_user, github_id: 12345, username: "alice_old", avatar_url: "old_url")
      end

      it "updates existing user data" do
        described_class.process(user_records)

        alice = GithubUser.find_by(github_id: 12345)
        expect(alice.username).to eq("alice")
        expect(alice.avatar_url).to eq("https://avatars.githubusercontent.com/u/12345")
      end
    end
  end
end
