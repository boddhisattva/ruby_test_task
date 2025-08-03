# frozen_string_literal: true

module GithubUsers
  class BulkProcessor
    def self.process(user_records)
      return {} if user_records.empty?

      # Try bulk upsert first (handles 99% of cases)
      attempt_bulk_upsert(user_records)
      build_user_lookup_map(user_records)
    end

    private
      def self.attempt_bulk_upsert(user_records)
        GithubUser.upsert_all(user_records, unique_by: :github_id)
      end

      def self.build_user_lookup_map(user_records)
        GithubUser.where(github_id: user_records.map { |u| u[:github_id] })
                  .pluck(:github_id, :id)
                  .to_h
      end
  end
end
