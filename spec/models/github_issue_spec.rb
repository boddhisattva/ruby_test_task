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
#  idx_on_owner_name_repository_name_issue_number_cc5010a1fc  (owner_name,repository_name,issue_number) UNIQUE
#  idx_on_owner_name_repository_name_state_a94b2775c7         (owner_name,repository_name,state)
#  index_github_issues_on_github_user_id                      (github_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (github_user_id => github_users.id)
#
require 'rails_helper'

RSpec.describe GithubIssue, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
