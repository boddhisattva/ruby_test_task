# == Schema Information
#
# Table name: github_issues
#
#  id                                                             :bigint           not null, primary key
#  body(The body of the issue)                                    :text
#  issue_created_at(The date and time when the issue was created) :datetime         not null
#  issue_number(The unique identifier for the issue)              :integer          not null
#  issue_updated_at(The date and time when the issue was updated) :datetime         not null
#  owner_name(The owner of the repository)                        :string           not null
#  repository_name(The name of the repository)                    :string           not null
#  state(The current state of the issue (open or closed))         :string           not null
#  title(The title of the issue)                                  :string           not null
#  created_at                                                     :datetime         not null
#  updated_at                                                     :datetime         not null
#  github_user_id                                                 :bigint           not null
#
# Indexes
#
#  idx_github_issues_owner_name_repository_name               (owner_name,repository_name)
#  idx_github_issues_repo_issue_created_at                    (owner_name,repository_name,issue_created_at)
#  idx_github_issues_repo_issue_updated_at                    (owner_name,repository_name,issue_updated_at)
#  idx_github_issues_repo_updated_at                          (owner_name,repository_name,updated_at)
#  idx_on_owner_name_repository_name_issue_number_cc5010a1fc  (owner_name,repository_name,issue_number) UNIQUE
#  idx_on_owner_name_repository_name_state_a94b2775c7         (owner_name,repository_name,state)
#  index_github_issues_on_github_user_id                      (github_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (github_user_id => github_users.id)
#
# frozen_string_literal: true

require "rails_helper"

RSpec.describe GithubIssue do
  describe "associations" do
    it "belongs to github_user" do
      # Explicit setup: create issue with user association
      github_user = create(:github_user)
      github_issue = create(:github_issue, github_user:)

      expect(github_issue.github_user).to eq(github_user)
    end
  end

  describe "validations" do
    before do
      @github_user = create(:github_user)
    end

    it "validates presence of repository_name" do
      # Explicit setup: create issue with missing repository_name
      github_issue = build(:github_issue, repository_name: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:repository_name]).to include("can't be blank")
    end

    it "validates presence of owner_name" do
      # Explicit setup: create issue with missing owner_name
      github_issue = build(:github_issue, owner_name: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:owner_name]).to include("can't be blank")
    end

    it "validates presence of issue_number" do
      # Explicit setup: create issue with missing issue_number
      github_issue = build(:github_issue, issue_number: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:issue_number]).to include("can't be blank")
    end

    it "validates uniqueness of issue_number scoped to owner_name and repository_name" do
      # Explicit setup: create existing issue and duplicate
      create(:github_issue, owner_name: "owner", repository_name: "repo", issue_number: 1, github_user: @github_user)
      duplicate_issue = build(:github_issue, owner_name: "owner", repository_name: "repo", issue_number: 1,
github_user: @github_user)

      expect(duplicate_issue).not_to be_valid
      expect(duplicate_issue.errors[:issue_number]).to include("has already been taken")
    end

    it "allows same issue_number in different repositories" do
      # Explicit setup: create issues with same number but different repos
      create(:github_issue, owner_name: "owner1", repository_name: "repo1", issue_number: 1, github_user: @github_user)
      different_repo_issue = build(:github_issue, owner_name: "owner2", repository_name: "repo2", issue_number: 1,
github_user: @github_user)

      expect(different_repo_issue).to be_valid
    end

    it "validates presence of state" do
      # Explicit setup: create issue with missing state
      github_issue = build(:github_issue, state: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:state]).to include("can't be blank")
    end

    it "validates state inclusion in open and closed" do
      # Explicit setup: create issue with invalid state
      github_issue = build(:github_issue, state: "invalid_state", github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:state]).to include("is not included in the list")
    end

    it "accepts valid states" do
      # Explicit setup: test both valid states
      open_issue = build(:github_issue, state: "open", github_user: @github_user)
      closed_issue = build(:github_issue, state: "closed", github_user: @github_user)

      expect(open_issue).to be_valid
      expect(closed_issue).to be_valid
    end

    it "validates presence of title" do
      # Explicit setup: create issue with missing title
      github_issue = build(:github_issue, title: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:title]).to include("can't be blank")
    end

    it "validates presence of issue_created_at" do
      # Explicit setup: create issue with missing issue_created_at
      github_issue = build(:github_issue, issue_created_at: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:issue_created_at]).to include("can't be blank")
    end

    it "validates presence of issue_updated_at" do
      # Explicit setup: create issue with missing issue_updated_at
      github_issue = build(:github_issue, issue_updated_at: nil, github_user: @github_user)

      expect(github_issue).not_to be_valid
      expect(github_issue.errors[:issue_updated_at]).to include("can't be blank")
    end

    it "is valid with all required attributes" do
      # Explicit setup: create issue with all valid attributes
      github_issue = build(:github_issue, github_user: @github_user)

      expect(github_issue).to be_valid
    end
  end

  describe "scopes" do
    before do
      @github_user = create(:github_user)
      @open_issue = create(:github_issue, state: "open", owner_name: "owner", repository_name: "repo",
github_user: @github_user)
      @closed_issue = create(:github_issue, state: "closed", owner_name: "owner", repository_name: "repo",
github_user: @github_user)
      @other_repo_issue = create(:github_issue, owner_name: "other_owner", repository_name: "other_repo",
github_user: @github_user)
    end

    describe "by_repository" do
      it "filters issues by repository" do
        # Explicit setup: test repository filtering
        filtered_issues = GithubIssue.by_repository("owner/repo")

        expect(filtered_issues).to include(@open_issue, @closed_issue)
        expect(filtered_issues).not_to include(@other_repo_issue)
      end

      it "returns none for blank repository" do
        # Explicit setup: test with blank repository
        filtered_issues = GithubIssue.by_repository("")

        expect(filtered_issues).to be_empty
      end

      it "returns none for nil repository" do
        # Explicit setup: test with nil repository
        filtered_issues = GithubIssue.by_repository(nil)

        expect(filtered_issues).to be_empty
      end
    end

    describe "by_state" do
      it "filters issues by open state" do
        # Explicit setup: test open state filtering
        open_issues = GithubIssue.by_state("open")

        expect(open_issues).to include(@open_issue)
        expect(open_issues).not_to include(@closed_issue)
      end

      it "filters issues by closed state" do
        # Explicit setup: test closed state filtering
        closed_issues = GithubIssue.by_state("closed")

        expect(closed_issues).to include(@closed_issue)
        expect(closed_issues).not_to include(@open_issue)
      end

      it "returns all issues for 'all' state" do
        # Explicit setup: test 'all' state filtering
        all_issues = GithubIssue.by_state("all")

        expect(all_issues).to include(@open_issue, @closed_issue, @other_repo_issue)
      end

      it "returns all issues for blank state" do
        # Explicit setup: test blank state filtering
        all_issues = GithubIssue.by_state("")

        expect(all_issues).to include(@open_issue, @closed_issue, @other_repo_issue)
      end
    end
  end
end
