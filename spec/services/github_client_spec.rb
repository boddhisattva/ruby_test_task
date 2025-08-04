# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSync::GithubClient do
  let(:client) { described_class.new }
  let(:repository) { "storyblok/storyblok" }
  let(:octokit_client) { instance_double(Octokit::Client) }
  let(:mock_response) { instance_double(Sawyer::Response) }
  let(:mock_headers) { { "link" => 'https://api.github.com/user/repos?page=3&per_page=100>; rel="next"' } }

  before do
    allow(Octokit::Client).to receive(:new).and_return(octokit_client)
    allow(octokit_client).to receive(:last_response).and_return(mock_response)
  end

  describe "#initialize" do
    it "creates an Octokit client with access token" do
      described_class.new
      expect(Octokit::Client).to have_received(:new).with(
        access_token: Rails.application.credentials.github.api_token
      )
    end

    it "stores client in instance variable" do
      expect(client.client).to eq(octokit_client)
    end
  end

  describe "#fetch_issues" do
    let(:options) { { state: "all", per_page: 100 } }
    let(:issue_with_pr) { OpenStruct.new(number: 1, title: "Issue 1", pull_request: true) }
    let(:regular_issue) { OpenStruct.new(number: 2, title: "Issue 2", pull_request: nil) }
    let(:mock_issues) { [issue_with_pr, regular_issue] }

    context "when API request succeeds" do
      before do
        allow(octokit_client).to receive(:issues).with(repository, options).and_return(mock_issues)
      end

      it "fetches issues from GitHub API" do
        client.fetch_issues(repository, options)
        expect(octokit_client).to have_received(:issues).with(repository, options)
      end

      it "filters out pull requests" do
        result = client.fetch_issues(repository, options)
        expect(result).to eq([regular_issue])
        expect(result).not_to include(issue_with_pr)
      end

      it "returns all issues when none are pull requests" do
        no_pr_issues = [regular_issue, OpenStruct.new(number: 3, title: "Issue 3", pull_request: nil)]
        allow(octokit_client).to receive(:issues).and_return(no_pr_issues)

        result = client.fetch_issues(repository, options)
        expect(result).to eq(no_pr_issues)
      end
    end

    context "when API request fails" do
      let(:error_message) { "API rate limit exceeded" }

      before do
        allow(octokit_client).to receive(:issues).and_raise(StandardError.new(error_message))
        allow(Rails.logger).to receive(:error)
      end

      it "logs error message" do
        client.fetch_issues(repository, options)
        expect(Rails.logger).to have_received(:error).with("Failed to fetch issues: #{error_message}")
      end

      it "returns empty array" do
        result = client.fetch_issues(repository, options)
        expect(result).to eq([])
      end

      it "handles different error types gracefully" do
        allow(octokit_client).to receive(:issues).and_raise(Octokit::TooManyRequests)
        result = client.fetch_issues(repository, options)
        expect(result).to eq([])
      end
    end

    context "when all issues are pull requests" do
      let(:all_prs) { [issue_with_pr, OpenStruct.new(number: 3, pull_request: true)] }

      before do
        allow(octokit_client).to receive(:issues).and_return(all_prs)
      end

      it "returns empty array" do
        result = client.fetch_issues(repository, options)
        expect(result).to eq([])
      end
    end
  end

  describe "#has_next_page?" do
    context "when response has next page link" do
      before do
        allow(mock_response).to receive(:headers).and_return(mock_headers)
      end

      it "returns true" do
        expect(client.has_next_page?).to be true
      end
    end

    context "when response has no next page link" do
      let(:headers_without_next) { { "link" => 'https://api.github.com/user/repos?page=1&per_page=100>; rel="prev"' } }

      before do
        allow(mock_response).to receive(:headers).and_return(headers_without_next)
      end

      it "returns false" do
        expect(client.has_next_page?).to be false
      end
    end

    context "when response has no link header" do
      before do
        allow(mock_response).to receive(:headers).and_return({})
      end

      it "returns false" do
        expect(client.has_next_page?).to be false
      end
    end

    context "when there is no response" do
      before do
        allow(octokit_client).to receive(:last_response).and_return(nil)
      end

      it "returns false" do
        expect(client.has_next_page?).to be false
      end
    end

    context "when response headers are nil" do
      before do
        allow(mock_response).to receive(:headers).and_return(nil)
      end

      it "returns false" do
        expect(client.has_next_page?).to be false
      end
    end
  end

  describe "#extract_next_url" do
    let(:next_rel) { instance_double(Sawyer::Relation, href: "https://api.github.com/repos/owner/repo/issues?page=2") }

    context "when response has next relation" do
      before do
        allow(mock_response).to receive(:rels).and_return({ next: next_rel })
      end

      it "returns next URL" do
        result = client.extract_next_url
        expect(result).to eq("https://api.github.com/repos/owner/repo/issues?page=2")
      end
    end

    context "when response has no next relation" do
      before do
        allow(mock_response).to receive(:rels).and_return({})
      end

      it "returns nil" do
        result = client.extract_next_url
        expect(result).to be_nil
      end
    end

    context "when there is no response" do
      before do
        allow(octokit_client).to receive(:last_response).and_return(nil)
      end

      it "returns nil" do
        result = client.extract_next_url
        expect(result).to be_nil
      end
    end

    context "when response rels is nil" do
      before do
        allow(mock_response).to receive(:rels).and_return(nil)
      end

      it "returns nil" do
        result = client.extract_next_url
        expect(result).to be_nil
      end
    end
  end
end
