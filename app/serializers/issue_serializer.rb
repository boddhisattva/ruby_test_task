# frozen_string_literal: true

class IssueSerializer
  include Alba::Resource

  attributes :issue_number, :state, :title, :body

  one :github_user, serializer: GithubUserSerializer

  attribute :created_at do |issue|
    issue.issue_created_at&.iso8601
  end

  attribute :updated_at do |issue|
    issue.issue_updated_at&.iso8601
  end
end
