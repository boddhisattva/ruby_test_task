# frozen_string_literal: true

require "rails_helper"

RSpec.describe IssueSerializer do
  it "serializes basic attributes" do
    issue = create(:github_issue)
    serialized = JSON.parse(described_class.new(issue).serialize)

    expect(serialized).to include(
      "number" => issue.issue_number,
      "state" => issue.state,
      "title" => issue.title,
      "body" => issue.body
    )
  end

  it "serializes timestamps in ISO8601 format" do
    issue = create(:github_issue)
    serialized = JSON.parse(described_class.new(issue).serialize)

    expect(serialized["created_at"]).to eq(issue.issue_created_at.iso8601)
    expect(serialized["updated_at"]).to eq(issue.issue_updated_at.iso8601)
  end

  it "includes associated user" do
    issue = create(:github_issue)
    serialized = JSON.parse(described_class.new(issue).serialize)

    expect(serialized["user"]).to include(
      "login" => issue.github_user.username,
      "avatar_url" => issue.github_user.avatar_url,
      "url" => issue.github_user.api_url,
      "type" => issue.github_user.account_type
    )
  end
end
