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
class GithubUser < ApplicationRecord
  validates :github_id, presence: true, uniqueness: true
  validates :username, presence: true, uniqueness: true
  validates :avatar_url, presence: true
  validates :account_type, presence: true
  validates :api_url, presence: true
end
