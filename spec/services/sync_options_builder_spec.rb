# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubSync::SyncOptionsBuilder do
  let(:repository) { "storyblok/storyblok" }
  let(:page_number) { 1 }
  let(:builder) { described_class.new(repository, page_number) }

  describe "#build_options_for_initial_pagination" do
    context "for initial sync (no existing data)" do
      before do
        # Mock no existing issues
        allow(GithubIssue).to receive_message_chain(:by_repository, :maximum)
          .with(:issue_updated_at).and_return(nil)
      end

      it "builds basic options without sorting for compatibility" do
        options = builder.build_options_for_initial_pagination

        expect(options).to eq({
          state: "all",
          per_page: 100
        })
      end
    end

    context "for incremental sync (has existing data)" do
      let(:last_sync_time) { 2.days.ago }

      before do
        # Mock existing issues
        allow(GithubIssue).to receive_message_chain(:by_repository, :maximum)
          .with(:issue_updated_at).and_return(last_sync_time)
      end

      it "builds options with sorting and since parameter" do
        options = builder.build_options_for_initial_pagination

        expect(options[:state]).to eq("all")
        expect(options[:per_page]).to eq(100)
        expect(options[:sort]).to eq("updated")
        expect(options[:direction]).to eq("desc")
        expect(options[:since]).to be_present
      end

      it "adds 1-minute buffer to since parameter" do
        options = builder.build_options_for_initial_pagination
        expected_since = (last_sync_time - 1.minute).iso8601

        expect(options[:since]).to eq(expected_since)
      end
    end

    context "without page number" do
      it "handles builder without page number" do
        builder_without_page = described_class.new(repository)
        options = builder_without_page.build_options_for_initial_pagination

        expect(options[:state]).to eq("all")
        expect(options[:per_page]).to eq(100)
        expect(options).not_to have_key(:page)
      end
    end
  end

  describe "edge cases" do
    context "with nil repository" do
      it "handles nil repository gracefully" do
        builder = described_class.new(nil, 1)

        expect { builder.build_options_for_initial_pagination }.not_to raise_error
      end
    end

    context "with empty repository string" do
      it "handles empty repository string" do
        builder = described_class.new("", 1)

        expect { builder.build_options_for_initial_pagination }.not_to raise_error
      end
    end

    context "with zero page number" do
      it "handles zero page number" do
        builder = described_class.new(repository, 0)
        options = builder.build_options_for_initial_pagination

        # Page number is not included in the current implementation
        expect(options).not_to have_key(:page)
      end
    end

    context "with negative page number" do
      it "handles negative page number" do
        builder = described_class.new(repository, -1)
        options = builder.build_options_for_initial_pagination

        # Page number is not included in the current implementation
        expect(options).not_to have_key(:page)
      end
    end
  end

  describe "integration with LastSyncTimestampFinder" do
    it "uses timestamp finder to determine sync strategy" do
      timestamp_finder = instance_double(GithubSync::LastSyncTimestampFinder)
      allow(GithubSync::LastSyncTimestampFinder).to receive(:new)
        .with(repository).and_return(timestamp_finder)

      builder = described_class.new(repository, 1)

      # Test initial sync path
      allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(false)

      options = builder.build_options_for_initial_pagination
      expect(options).not_to have_key(:since)

      # Test incremental sync path
      allow(timestamp_finder).to receive(:should_filter_by_time?).and_return(true)
      allow(timestamp_finder).to receive(:find_last_synced_at).and_return(1.day.ago)

      options = builder.build_options_for_initial_pagination
      expect(options).to have_key(:since)
    end
  end

  describe "different repository formats" do
    it "works with various repository name formats" do
      repositories = [
        "owner/repo",
        "microsoft/terminal",
        "facebook/react",
        "storyblok/storyblok-js-client"
      ]

      repositories.each do |repo|
        builder = described_class.new(repo, 1)

        expect { builder.build_options_for_initial_pagination }.not_to raise_error
      end
    end
  end
end
