# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Issues" do
  describe "GET /api/v1/repos/:provider/:owner/:repo/issues" do
    context "end-to-end GitHub sync integration", :vcr, :sidekiq_inline do
      let(:provider) { "github" }
      let(:owner) { "octocat" }
      let(:repo) { "Hello-World" }
      let(:repository) { "#{owner}/#{repo}" }

      it "syncs issues from GitHub API when no data exists" do
        # This test will use VCR to record/replay GitHub API responses
        VCR.use_cassette("github_sync_octocat_hello_world_issues") do
          # Trigger the sync by accessing the endpoint with state=all
          get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues", params: { state: "all" }

          # Should return OK status even if sync is triggered
          expect(response).to have_http_status(:ok)

          # Verify that issues were synced (octocat/Hello-World has limited issues)
          synced_issues = GithubIssue.where(repository_name: repo, owner_name: owner)
          expect(synced_issues.count).to be > 0

          # Verify users were created
          expect(GithubUser.count).to be > 0

          # Store the actual count for other tests
          actual_count = synced_issues.count

          # Verify X-Total-Count header matches database count
          expect(response.headers["X-Total-Count"]).to eq(actual_count.to_s)

          # Verify the response includes paginated issues (default pagination applies)
          json = JSON.parse(response.body)
          expect(json).to be_an(Array)
          expect(json.size).to be > 0
          expect(json.size).to be <= 25 # Default per_page from IssuesFetcher

          # Verify complete issue structure matches IssueSerializer
          first_issue = json.first
          expect(first_issue).to include(
            "issue_number",
            "state",
            "title",
            "body",
            "created_at",
            "updated_at",
            "github_user"
          )

          # Verify user structure matches GithubUserSerializer
          expect(first_issue["github_user"]).to include(
            "username",
            "avatar_url",
            "api_url",
            "type"
          )

          # Verify data types
          expect(first_issue["issue_number"]).to be_a(Integer)
          expect(first_issue["state"]).to be_in(["open", "closed"])
          expect(first_issue["title"]).to be_a(String)
          expect(first_issue["created_at"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
          expect(first_issue["updated_at"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/)
        end
      end

      it "handles pagination correctly with synced data" do
        VCR.use_cassette("github_sync_octocat_hello_world_pagination") do
          # Sync data first with state=all
          get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues", params: { state: "all" }

          # Get the actual total count
          total_synced = GithubIssue.where(repository_name: repo, owner_name: owner).count
          expect(total_synced).to be > 0

          # Test pagination with per_page=2 (smaller for Hello-World repo)
          per_page_size = [total_synced / 2, 2].max
          get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues",
params: { per_page: per_page_size, page: 1, state: "all" }

          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)

          # First page should have at most per_page_size items
          expect(json.size).to be <= per_page_size
          expect(json.size).to be > 0

          # Verify pagination headers
          expect(response.headers["X-Total-Count"]).to eq(total_synced.to_s)

          # Test page 2 if there are enough items
          if total_synced > per_page_size
            get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues",
params: { per_page: per_page_size, page: 2, state: "all" }

            page2_json = JSON.parse(response.body)
            expect(page2_json.size).to be <= per_page_size
            expect(response.headers["X-Total-Count"]).to eq(total_synced.to_s)
          end
        end
      end

      it "filters synced issues by status" do
        VCR.use_cassette("github_sync_octocat_hello_world_filter") do
          # Sync data first with state=all to get both open and closed
          get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues", params: { state: "all" }

          # Get actual counts (Hello-World may have different distribution)
          all_issues = GithubIssue.where(repository_name: repo, owner_name: owner)
          total_count = all_issues.count
          open_count = all_issues.where(state: "open").count
          closed_count = all_issues.where(state: "closed").count

          expect(total_count).to be > 0
          expect(open_count + closed_count).to eq(total_count)

          # Test filtering by open status (if any exist)
          if open_count > 0
            get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues", params: { status: "open", state: "all" }

            expect(response).to have_http_status(:ok)
            json = JSON.parse(response.body)
            expect(json.size).to be > 0
            expect(json.size).to be <= 25 # Default pagination applies
            expect(json).to all(include("state" => "open"))
            expect(response.headers["X-Total-Count"]).to eq(open_count.to_s)
          end

          # Test filtering by closed status (if any exist)
          if closed_count > 0
            get "/api/v1/repos/#{provider}/#{owner}/#{repo}/issues", params: { status: "closed", state: "all" }

            expect(response).to have_http_status(:ok)
            json = JSON.parse(response.body)
            expect(json.size).to be > 0
            expect(json.size).to be <= 25 # Default pagination applies
            expect(json).to all(include("state" => "closed"))
            expect(response.headers["X-Total-Count"]).to eq(closed_count.to_s)
          end
        end
      end

      it "performs initial sync followed by incremental sync", :vcr, :sidekiq_inline do
        # Use boddhisattva/ruby_test_task as test repository
        test_provider = "github"
        test_owner = "boddhisattva"
        test_repo = "ruby_test_task"
        test_repository = "#{test_owner}/#{test_repo}"

        VCR.use_cassette("github_incremental_sync_with_changes") do
          # Clear any existing data for this repository
          # GithubIssue.where(repository_name: test_repo, owner_name: test_owner).destroy_all
          # GithubUser.destroy_all


          # === STEP 1: Initial Sync (no existing data) ===
          # This should trigger a full sync since no data exists
          get "/api/v1/repos/#{test_provider}/#{test_owner}/#{test_repo}/issues", params: { state: "all" }

          expect(response).to have_http_status(:ok)

          # Verify issues were synced from the repository
          initial_issues = GithubIssue.where(repository_name: test_repo, owner_name: test_owner)
          initial_count = initial_issues.count
          expect(initial_count).to be > 0

          # Verify users were created
          initial_users_count = GithubUser.count
          expect(initial_users_count).to be > 0



          # Verify the API response matches what we synced
          json = JSON.parse(response.body)
          expect(json.size).to be > 0
          expect(response.headers["X-Total-Count"]).to eq(initial_count.to_s)

          # Capture initial state of issue #7 (should be open)
          initial_issue_7 = initial_issues.find_by(issue_number: 7)
          expect(initial_issue_7).to be_present
          expect(initial_issue_7.state).to eq("open")

          # === STEP 2: Wait and prepare for incremental sync ===
          # Advance time to simulate passage of time and make data "stale"
          # Use a longer time gap to ensure incremental sync is triggered
          travel_to(1.hour.from_now) do
            # Clear cache to force fresh data check


            # === STEP 3: Incremental Sync (with existing data) ===
            # This should trigger incremental sync since data exists but is stale
            # The VCR cassette will mock GitHub API to return:
            # 1. A new issue (#9) with a new user (newuser)
            # 2. An updated existing issue (#7) that changed from open to closed

            get "/api/v1/repos/#{test_provider}/#{test_owner}/#{test_repo}/issues", params: { state: "all" }

            expect(response).to have_http_status(:ok)

            # Verify incremental sync occurred
            post_incremental_issues = GithubIssue.where(repository_name: test_repo, owner_name: test_owner)
            post_incremental_count = post_incremental_issues.count

            # Should have the original issues plus the new issue from GitHub API
            # The VCR cassette returns specific issues, so we expect them to be present
            expect(post_incremental_count).to be >= initial_count

            # Verify the new issue from our VCR cassette was synced
            new_issue = post_incremental_issues.find_by(issue_number: 9)
            expect(new_issue).to be_present
            expect(new_issue.title).to eq("New issue created during incremental sync test")
            expect(new_issue.state).to eq("open")

            # Verify the new user was created
            new_user = GithubUser.find_by(username: "newuser")
            expect(new_user).to be_present
            expect(new_user.github_id).to eq(99999)

            # Verify the updated existing issue was synced
            updated_issue = post_incremental_issues.find_by(issue_number: 7)
            expect(updated_issue).to be_present
            expect(updated_issue.state).to eq("closed") # Changed from open to closed
            expect(updated_issue.issue_updated_at).to be > initial_issue_7.issue_updated_at

            # Verify API response reflects updated count
            json = JSON.parse(response.body)
            expect(json.size).to be > 0
            expect(response.headers["X-Total-Count"]).to eq(post_incremental_count.to_s)

            # Verify the API response reflects the updated data
            # The response might contain different issues due to pagination
            expect(json.size).to be > 0
            expect(response.headers["X-Total-Count"]).to eq(post_incremental_count.to_s)

            # === STEP 4: Verify the sync actually happened ===
            # The sync should have processed the mocked GitHub API response
            # and updated our database with new/updated issues
            expect(response).to have_http_status(:ok)
            expect(response.headers["X-Total-Count"]).to eq(post_incremental_count.to_s)
          end
        end
      end
    end
  end
end
