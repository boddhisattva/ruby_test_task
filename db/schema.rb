# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_07_30_115228) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "github_issues", force: :cascade do |t|
    t.string "repository_name", null: false, comment: "The name of the repository"
    t.string "owner_name", null: false, comment: "The owner of the repository"
    t.integer "issue_number", null: false, comment: "The unique identifier for the issue"
    t.string "state", null: false, comment: "The current state of the issue (open or closed)"
    t.string "title", null: false, comment: "The title of the issue"
    t.text "body", comment: "The body of the issue"
    t.bigint "github_user_id", null: false
    t.datetime "issue_created_at", null: false, comment: "The date and time when the issue was created"
    t.datetime "issue_updated_at", null: false, comment: "The date and time when the issue was updated"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_user_id"], name: "index_github_issues_on_github_user_id"
    t.index ["owner_name", "repository_name", "issue_number"], name: "idx_on_owner_name_repository_name_issue_number_cc5010a1fc", unique: true
    t.index ["owner_name", "repository_name", "state"], name: "idx_on_owner_name_repository_name_state_a94b2775c7"
    t.check_constraint "issue_number > 0", name: "github_issues_issue_number_positive"
    t.check_constraint "state::text = ANY (ARRAY['open'::character varying, 'closed'::character varying]::text[])", name: "github_issues_state_valid"
  end

  create_table "github_users", force: :cascade do |t|
    t.bigint "github_id", null: false, comment: "This is the unique identifier for the user on GitHub"
    t.string "username", null: false, comment: "This indicates the username or handle of the account"
    t.string "avatar_url", null: false, comment: "The URL to the user's avatar"
    t.string "account_type", null: false, comment: "Indicates whether the account is a User or Organization"
    t.string "api_url", null: false, comment: "The URL to the user's API endpoint"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_id"], name: "index_github_users_on_github_id", unique: true
    t.index ["username"], name: "index_github_users_on_username", unique: true
  end

  add_foreign_key "github_issues", "github_users"
end
