# frozen_string_literal: true

require "rails_helper"

RSpec.describe IssuesFetcher do
  let(:repository) { "storyblok/storyblok" }
  let(:user) { create(:github_user) }

  before do
    # Create test issues with different timestamps to test cache version calculation
    @issue_oldest = create(:github_issue,
      owner_name: "storyblok",
      repository_name: "storyblok",
      github_user: user,
      issue_created_at: 2.days.ago,
      issue_updated_at: 2.days.ago
    )

    @issue_newest_created = create(:github_issue,
      owner_name: "storyblok",
      repository_name: "storyblok",
      github_user: user,
      issue_created_at: 1.hour.ago,  # Most recent creation
      issue_updated_at: 1.day.ago
    )

    @issue_newest_updated = create(:github_issue,
      owner_name: "storyblok",
      repository_name: "storyblok",
      github_user: user,
      issue_created_at: 1.day.ago,
      issue_updated_at: 30.minutes.ago  # Most recent update
    )
  end

  describe "#initialize" do
    context "when cv parameter is provided" do
      it "uses the provided cache version" do
        fetcher = described_class.new(repository, cv: 123456)
        expect(fetcher.cv).to eq(123456)
      end
    end

    context "when cv parameter is not provided" do
      it "calculates current cache version automatically" do
        fetcher = described_class.new(repository)

        # Should use the maximum of issue_created_at and issue_updated_at timestamps
        expected_cv = [@issue_newest_created.issue_created_at.to_i, @issue_newest_updated.issue_updated_at.to_i].max
        expect(fetcher.cv).to eq(expected_cv)
      end
    end
  end


  describe "#fetch" do
    let(:fetcher) { described_class.new(repository, status: "open", page: 1) }
    let(:cache_key) { fetcher.send(:cache_key_with_cv) }

    before do
      # Clear cache before each test
      Rails.cache.clear
    end

    context "when cache is empty" do
      it "fetches data from database" do
        expect(GithubIssue).to receive(:includes).and_call_original
        expect(GithubIssue).to receive(:by_repository).at_least(:once).and_call_original
        expect(GithubIssue).to receive(:by_state).and_call_original

        result = fetcher.fetch

        expect(result).to have_key(:issues)
        expect(result).to have_key(:total_count)
        expect(result).to have_key(:pagy)
      end

      it "stores result in cache with correct key" do
        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: 1.year).and_call_original

        result = fetcher.fetch

        # Verify that Rails.cache.fetch was called with the correct parameters
        # This verifies caching behavior without relying on cache backend specifics
        expect(result).to have_key(:issues)
        expect(result).to have_key(:total_count)
        expect(result).to have_key(:pagy)
      end

      it "sets cache expiration to 1 year" do
        # Spy on Rails.cache to verify expires_in parameter
        allow(Rails.cache).to receive(:fetch).and_call_original

        fetcher.fetch

        expect(Rails.cache).to have_received(:fetch).with(cache_key, expires_in: 1.year)
      end

      it "returns correctly structured data with issues, total_count, and pagy" do
        result = fetcher.fetch

        expect(result).to be_a(Hash)
        expect(result).to have_key(:issues)
        expect(result).to have_key(:total_count)
        expect(result).to have_key(:pagy)

        expect(result[:issues]).to be_an(ActiveRecord::Relation)
        expect(result[:total_count]).to be_an(Integer)
        expect(result[:pagy]).to respond_to(:count)
      end

      it "applies proper filtering and ordering from database" do
        # Create a closed issue to test filtering
        closed_issue = create(:github_issue,
          owner_name: "storyblok",
          repository_name: "storyblok",
          github_user: user,
          state: "closed",
          issue_updated_at: 1.hour.ago
        )

        result = fetcher.fetch

        # Should only include open issues (status: "open")
        expect(result[:issues].pluck(:state)).to all(eq("open"))
        expect(result[:issues]).not_to include(closed_issue)

        # Should be ordered by issue_created_at desc
        created_ats = result[:issues].pluck(:issue_created_at)
        expect(created_ats).to eq(created_ats.sort.reverse)
      end
    end

    context "when cache has data" do
      let(:cached_data) do
        {
          issues: [@issue_oldest, @issue_newest_created],
          total_count: 2,
          pagy: double("pagy", count: 2)
        }
      end

      it "returns cached data without hitting database" do
        # Mock Rails.cache.fetch to return cached_data directly
        expect(Rails.cache).to receive(:fetch).with(fetcher.send(:cache_key_with_cv),
expires_in: 1.year).and_return(cached_data)

        # Expect no database queries to be made for the actual fetch
        expect(GithubIssue).not_to receive(:includes)

        result = fetcher.fetch

        expect(result).to eq(cached_data)
      end

      it "respects cache version in key" do
        # Create fetcher with different cache version
        different_cv_fetcher = described_class.new(repository, status: "open", page: 1, cv: 999999)
        different_cache_key = different_cv_fetcher.send(:cache_key_with_cv)

        # This should hit database since cache key is different
        expect(Rails.cache).to receive(:fetch).with(different_cache_key, expires_in: 1.year).and_call_original
        expect(GithubIssue).to receive(:includes).and_call_original
        expect(GithubIssue).to receive(:by_repository).at_least(:once).and_call_original

        different_cv_fetcher.fetch
      end

      it "uses exact cache key matching including all parameters" do
        # Different status should use different cache key
        different_status_fetcher = described_class.new(repository, status: "closed", page: 1, cv: fetcher.cv)
        different_status_key = different_status_fetcher.send(:cache_key_with_cv)

        expect(Rails.cache).to receive(:fetch).with(different_status_key, expires_in: 1.year).and_call_original
        expect(GithubIssue).to receive(:includes).and_call_original
        expect(GithubIssue).to receive(:by_repository).at_least(:once).and_call_original

        different_status_fetcher.fetch
      end

      it "different page numbers use different cache keys" do
        # Test that different page uses different cache key by comparing keys
        different_page_fetcher = described_class.new(repository, status: "open", page: 2, cv: fetcher.cv)
        different_page_key = different_page_fetcher.send(:cache_key_with_cv)
        original_page_key = fetcher.send(:cache_key_with_cv)

        # Verify keys are different
        expect(different_page_key).not_to eq(original_page_key)
        expect(different_page_key).to include("page_2")
        expect(original_page_key).to include("page_1")
      end
    end

    context "when Rails.cache fails" do
      before do
        # Mock cache failure
        allow(Rails.cache).to receive(:fetch).and_raise(StandardError.new("Cache connection failed"))
      end

      it "raises cache error" do
        # Current implementation doesn't handle cache failures gracefully
        # The error bubbles up from Rails.cache.fetch
        expect { fetcher.fetch }.to raise_error(StandardError, "Cache connection failed")
      end
    end

    context "pagination behavior" do
      before do
        # Create enough issues to test pagination
        10.times do |i|
          create(:github_issue,
            owner_name: "storyblok",
            repository_name: "storyblok",
            github_user: user,
            state: "open",
            issue_updated_at: i.hours.ago
          )
        end
      end

      it "respects per_page limit of 25" do
        result = fetcher.fetch

        expect(result[:issues].size).to be <= 25
      end

      it "calculates total_count correctly regardless of pagination" do
        result = fetcher.fetch

        total_open_issues = GithubIssue.by_repository(repository).by_state("open").count
        expect(result[:total_count]).to eq(total_open_issues)
      end

      it "includes pagy object for pagination metadata" do
        result = fetcher.fetch

        expect(result[:pagy]).to respond_to(:count)
        expect(result[:pagy]).to respond_to(:page)
        expect(result[:pagy]).to respond_to(:pages)
      end
    end

    context "eager loading optimization" do
      it "includes github_user association to prevent N+1 queries" do
        expect(GithubIssue).to receive(:includes).with(:github_user).and_call_original

        fetcher.fetch
      end

      it "allows accessing github_user without additional queries" do
        result = fetcher.fetch

        # Verify that github_user is loaded (no additional query needed)
        first_issue = result[:issues].first
        if first_issue
          expect { first_issue.github_user.username }.not_to raise_error
          expect(first_issue.association(:github_user)).to be_loaded
        end
      end
    end
  end

  describe "filtering behavior" do
    let(:other_repo_user) { create(:github_user) }

    before do
      # Clear cache for clean filtering tests
      Rails.cache.clear

      # Create issues for different repositories to test repository filtering
      @other_repo_issue = create(:github_issue,
        owner_name: "different",
        repository_name: "repo",
        github_user: other_repo_user,
        state: "open",
        title: "Other repo issue",
        issue_updated_at: 30.minutes.ago
      )

      # Create closed issues in target repository to test status filtering
      @closed_issue_1 = create(:github_issue,
        owner_name: "storyblok",
        repository_name: "storyblok",
        github_user: user,
        state: "closed",
        title: "Closed issue 1",
        issue_updated_at: 25.minutes.ago
      )

      @closed_issue_2 = create(:github_issue,
        owner_name: "storyblok",
        repository_name: "storyblok",
        github_user: user,
        state: "closed",
        title: "Closed issue 2",
        issue_updated_at: 20.minutes.ago
      )
    end

    describe "repository filtering" do
      it "filters by repository" do
        fetcher = described_class.new("storyblok/storyblok", status: "all")
        result = fetcher.fetch

        # Should only include issues from storyblok/storyblok repository
        issues = result[:issues]
        expect(issues.pluck(:owner_name)).to all(eq("storyblok"))
        expect(issues.pluck(:repository_name)).to all(eq("storyblok"))

        # Should not include issues from other repositories
        issue_titles = issues.pluck(:title)
        expect(issue_titles).not_to include("Other repo issue")
      end

      it "returns empty results for non-existent repository" do
        fetcher = described_class.new("nonexistent/repo")
        result = fetcher.fetch

        expect(result[:issues]).to be_empty
        expect(result[:total_count]).to eq(0)
      end

      it "works with different repository format variations" do
        # Test with different repository
        different_repo_fetcher = described_class.new("different/repo")
        result = different_repo_fetcher.fetch

        expect(result[:issues].size).to eq(1)
        expect(result[:issues].first.title).to eq("Other repo issue")
        expect(result[:total_count]).to eq(1)
      end
    end

    describe "status filtering" do
      it "filters by status (open)" do
        fetcher = described_class.new("storyblok/storyblok", status: "open")
        result = fetcher.fetch

        # Should only include open issues
        expect(result[:issues].pluck(:state)).to all(eq("open"))

        # Should not include closed issues
        issue_titles = result[:issues].pluck(:title)
        expect(issue_titles).not_to include("Closed issue 1")
        expect(issue_titles).not_to include("Closed issue 2")

        # Count should reflect only open issues
        open_count = GithubIssue.by_repository("storyblok/storyblok").by_state("open").count
        expect(result[:total_count]).to eq(open_count)
      end

      it "filters by status (closed)" do
        fetcher = described_class.new("storyblok/storyblok", status: "closed")
        result = fetcher.fetch

        # Should only include closed issues
        expect(result[:issues].pluck(:state)).to all(eq("closed"))

        # Should include our closed issues
        issue_titles = result[:issues].pluck(:title)
        expect(issue_titles).to include("Closed issue 1")
        expect(issue_titles).to include("Closed issue 2")

        # Count should reflect only closed issues
        closed_count = GithubIssue.by_repository("storyblok/storyblok").by_state("closed").count
        expect(result[:total_count]).to eq(closed_count)
      end

      it "filters by status (all)" do
        fetcher = described_class.new("storyblok/storyblok", status: "all")
        result = fetcher.fetch

        # Should include both open and closed issues
        states = result[:issues].pluck(:state)
        expect(states).to include("open")
        expect(states).to include("closed")

        # Should include issues from all states
        issue_titles = result[:issues].pluck(:title)
        expect(issue_titles).to include("Closed issue 1")
        expect(issue_titles).to include("Closed issue 2")

        # Count should reflect all issues in repository
        all_count = GithubIssue.by_repository("storyblok/storyblok").count
        expect(result[:total_count]).to eq(all_count)
      end

      it 'defaults to "open" status when not specified' do
        fetcher = described_class.new("storyblok/storyblok")
        result = fetcher.fetch

        # Should behave same as status: "open"
        states = result[:issues].pluck(:state)
        expect(states).to all(eq("open"))

        open_count = GithubIssue.by_repository("storyblok/storyblok").by_state("open").count
        expect(result[:total_count]).to eq(open_count)
      end
    end

    describe "combined filtering" do
      it "applies both repository and status filters together" do
        fetcher = described_class.new("storyblok/storyblok", status: "closed")
        result = fetcher.fetch

        # Should only include closed issues from storyblok/storyblok
        issues = result[:issues]
        expect(issues.pluck(:owner_name)).to all(eq("storyblok"))
        expect(issues.pluck(:repository_name)).to all(eq("storyblok"))
        expect(issues.pluck(:state)).to all(eq("closed"))

        # Should not include issues from other repositories even if they match status
        issue_titles = issues.pluck(:title)
        expect(issue_titles).not_to include("Other repo issue")
      end

      it "maintains proper ordering after filtering" do
        fetcher = described_class.new("storyblok/storyblok", status: "all")
        result = fetcher.fetch

        # Should be ordered by issue_created_at desc
        created_ats = result[:issues].pluck(:issue_created_at)
        expect(created_ats).to eq(created_ats.sort.reverse)

        # Most recent should be first
        expect(result[:issues].first.issue_created_at).to be >= result[:issues].last.issue_created_at
      end
    end
  end
end
