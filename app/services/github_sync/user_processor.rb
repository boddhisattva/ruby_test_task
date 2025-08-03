# frozen_string_literal: true

module GithubSync
  class UserProcessor
    def process_users(issues)
      unique_users = extract_unique_users_from_issues(issues)
      return {} if unique_users.empty?

      user_records = build_user_records(unique_users)
      GithubUsers::BulkProcessor.process(user_records)
    end

    private
      def extract_unique_users_from_issues(issues)
        issues
          .map(&:user)
          .compact
          .uniq { |user_data| user_data.id }
      end

      def build_user_records(users)
        users.map do |user_data|
          {
            github_id: user_data.id,
            username: user_data.login,
            avatar_url: user_data.avatar_url,
            account_type: user_data.type,
            api_url: user_data.url,
            created_at: Time.current,
            updated_at: Time.current
          }
        end
      end
  end
end
