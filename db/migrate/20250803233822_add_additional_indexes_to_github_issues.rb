class AddAdditionalIndexesToGithubIssues < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :github_issues, [:owner_name, :repository_name],
              name: "idx_github_issues_owner_name_repository_name",
              comment: "Optimizes repository-based queries(e.g., by_repository scope) & sync operations", algorithm: :concurrently

    add_index :github_issues, [:owner_name, :repository_name, :issue_created_at],
              name: "idx_github_issues_repo_issue_created_at",
              comment: "Used in places like default ordering for issue display",
              algorithm: :concurrently

    add_index :github_issues, [:owner_name, :repository_name, :issue_updated_at],
              name: "idx_github_issues_repo_issue_updated_at",
              comment: "CRITICAL: Optimizes cache version calculation for issue_updated_at - affects every API request performance",
              algorithm: :concurrently

    add_index :github_issues, [:owner_name, :repository_name, :updated_at],
              name: "idx_github_issues_repo_updated_at",
              comment: "Stale data detection for sync coordination",
              algorithm: :concurrently
  end
end
