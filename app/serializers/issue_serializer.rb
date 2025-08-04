# frozen_string_literal: true

class IssueSerializer
  include Alba::Resource

  attributes :state, :title, :body

  attribute :number do |issue|
    issue.issue_number
  end

  attribute :user do |issue|
    GithubUserSerializer.new(issue.github_user).as_json
  end

  attribute :created_at do |issue|
    issue.issue_created_at&.iso8601
  end

  attribute :updated_at do |issue|
    issue.issue_updated_at&.iso8601
  end
end
