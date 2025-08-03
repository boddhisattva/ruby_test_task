# frozen_string_literal: true

module GithubSync
  class IssueBuilder
    def initialize(repository, user_id_map)
      @repository = repository
      @user_id_map = user_id_map
      @owner_name, @repository_name = repository.split("/")
    end

    def build_records(issues)
      issues.filter_map do |issue_data|
        build_single_record(issue_data)
      end
    end

    private
      def build_single_record(issue_data)
        github_user_id = @user_id_map[issue_data.user.id]

        if github_user_id.nil?
          Rails.logger.error "Failed to resolve user #{issue_data.user.id}"
          return nil
        end

        {
          owner_name: @owner_name,
          repository_name: @repository_name,
          issue_number: issue_data.number,
          github_user_id:,
          state: issue_data.state,
          title: issue_data.title,
          body: issue_data.body,
          issue_created_at: issue_data.created_at,
          issue_updated_at: issue_data.updated_at,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
  end
end
