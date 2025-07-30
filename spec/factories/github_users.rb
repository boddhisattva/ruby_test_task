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
FactoryBot.define do
  factory :github_user do
    sequence(:github_id) { |n| n }
    sequence(:username) { |n| "user#{n}" }
    avatar_url { Faker::Internet.url }
    account_type { "User" }
    api_url { "https://github.com/#{username}" }
  end
end
