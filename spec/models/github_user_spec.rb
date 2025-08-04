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
# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubUser do
  describe "validations" do
    it "validates presence of github_id" do
      # Explicit setup: create user with missing github_id
      github_user = build(:github_user, github_id: nil)

      expect(github_user).not_to be_valid
      expect(github_user.errors[:github_id]).to include("can't be blank")
    end

    it "validates uniqueness of github_id" do
      # Explicit setup: create existing user and duplicate
      create(:github_user, github_id: 12345)
      duplicate_user = build(:github_user, github_id: 12345)

      expect(duplicate_user).not_to be_valid
      expect(duplicate_user.errors[:github_id]).to include("has already been taken")
    end

    it "validates presence of username" do
      # Explicit setup: create user with missing username
      github_user = build(:github_user, username: nil)

      expect(github_user).not_to be_valid
      expect(github_user.errors[:username]).to include("can't be blank")
    end

    it "is valid with all required attributes" do
      # Explicit setup: create user with all valid attributes
      github_user = build(:github_user)

      expect(github_user).to be_valid
    end
  end
end
