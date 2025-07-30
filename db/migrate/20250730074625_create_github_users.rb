class CreateGithubUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :github_users do |t|
      t.bigint :github_id, null: false, comment: "This is the unique identifier for the user on GitHub"
      t.string :username, null: false, comment: "This indicates the username or handle of the account"
      t.string :avatar_url, null: false, comment: "The URL to the user's avatar"
      t.string :account_type, null: false, comment: "Indicates whether the account is a User or Organization"
      t.string :api_url, null: false, comment: "The URL to the user's API endpoint"
      t.timestamps
    end

    add_index :github_users, :github_id, unique: true
    add_index :github_users, :username, unique: true
  end
end
