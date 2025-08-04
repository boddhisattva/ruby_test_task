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
        return log_and_skip_no_user(issue_data) if missing_user?(issue_data)

        github_user_id = find_user_id(issue_data)
        return log_and_skip_unresolved_user(issue_data) if github_user_id.nil?

        build_issue_hash(issue_data, github_user_id)
      end

      def missing_user?(issue_data)
        issue_data.user.nil?
      end

      def log_and_skip_no_user(issue_data)
        Rails.logger.warn "Skipping issue #{issue_data.number} - no user"
        nil
      end

      def find_user_id(issue_data)
        @user_id_map[issue_data.user.id]
      end

      def log_and_skip_unresolved_user(issue_data)
        Rails.logger.error "Failed to resolve user #{issue_data.user.id}"
        nil
      end

      def build_issue_hash(issue_data, github_user_id)
        {
          owner_name: @owner_name,
          repository_name: @repository_name,
          issue_number: issue_data.number,
          github_user_id:,
          state: issue_data.state,
          title: sanitize_string(issue_data.title),
          body: sanitize_string(issue_data.body),
          issue_created_at: issue_data.created_at,
          issue_updated_at: issue_data.updated_at,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      def sanitize_string(str)
        return nil if str.nil?
        str.gsub("\0", "")
      end
  end
end
