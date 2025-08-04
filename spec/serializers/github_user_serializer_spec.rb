# frozen_string_literal: true

# == Schema Information
#
# Table name: github_users
#
#  id                                                                    :bigint           not null, primary key
#  account_type(Indicates whether the account is a User or Organization) :string           not null
#  api_url(The URL to the user's API endpoint)                           :string           not null
#  avatar_url(The URL to the user's avatar)                              :string           not null
#  username(This indicates the username or handle of the account)        :string           not null
#  created_at                                                            :datetime         not null
#  updated_at                                                            :datetime         not null
#  github_id(This is the unique identifier for the user on GitHub)       :bigint           not null
#
# Indexes
#
#  index_github_users_on_github_id  (github_id) UNIQUE
#  index_github_users_on_username   (username) UNIQUE
#
require "rails_helper"

RSpec.describe GithubUserSerializer do
  describe "serialization" do
    it "includes all required attributes" do
      github_user = build_stubbed(:github_user)
      serialized = JSON.parse(described_class.new(github_user).serialize)

      expect(serialized).to include(
        "login" => github_user.username,
        "avatar_url" => github_user.avatar_url,
        "url" => github_user.api_url,
        "type" => github_user.account_type
      )
    end

    it "handles nil values gracefully" do
      github_user = build_stubbed(:github_user, avatar_url: nil, api_url: nil)

      expect { described_class.new(github_user).serialize }.not_to raise_error

      serialized = JSON.parse(described_class.new(github_user).serialize)
      expect(serialized["avatar_url"]).to be_nil
      expect(serialized["api_url"]).to be_nil
    end

    it "integrates with Alba correctly" do
      github_user = build_stubbed(:github_user)

      expect(described_class.ancestors).to include(Alba::Resource)
      expect(described_class.new(github_user)).to respond_to(:serialize)

      serialized_result = described_class.new(github_user).serialize
      expect(serialized_result).to be_a(String)
      expect { JSON.parse(serialized_result) }.not_to raise_error
    end
  end
end
