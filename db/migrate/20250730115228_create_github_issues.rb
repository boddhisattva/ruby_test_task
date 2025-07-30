class CreateGithubIssues < ActiveRecord::Migration[7.1]
  def change
    create_table :github_issues do |t|
      t.string :repository_name, null: false, comment: "The name of the repository"
      t.string :owner_name, null: false, comment: "The owner of the repository"
      t.integer :issue_number, null: false, comment: "The unique identifier for the issue"
      t.string :state, null: false, comment: "The current state of the issue (open or closed)"
      t.string :title, null: false, comment: "The title of the issue"
      t.text :body, comment: "The body of the issue"
      t.references :github_user, null: false, foreign_key: true
      t.datetime :issue_created_at, null: false, comment: "The date and time when the issue was created"
      t.datetime :issue_updated_at, null: false, comment: "The date and time when the issue was updated"
      t.timestamps
    end

    add_index :github_issues, [:owner_name, :repository_name, :issue_number], unique: true
    add_index :github_issues, [:owner_name, :repository_name, :state]

    add_check_constraint :github_issues, "issue_number > 0", name: "github_issues_issue_number_positive"
    add_check_constraint :github_issues, "state IN ('open', 'closed')", name: "github_issues_state_valid"
  end
end
