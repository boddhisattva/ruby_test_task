# frozen_string_literal: true

module GithubSync
  class IssuePersister
    def initialize(repository)
      @repository = repository
    end

    def persist(api_returned_issues)
      return false if api_returned_issues.empty?

      existing_issues_data = fetch_existing_issue_data(api_returned_issues)
      new_or_updated_issues_to_be_persisted = select_new_or_updated_issues(api_returned_issues, existing_issues_data)

      return false if new_or_updated_issues_to_be_persisted.empty?

      ActiveRecord::Base.transaction do
        user_processor = UserProcessor.new
        user_id_map = user_processor.process_users(new_or_updated_issues_to_be_persisted)

        issue_builder = IssueBuilder.new(@repository, user_id_map)
        issue_records = issue_builder.build_records(new_or_updated_issues_to_be_persisted)

        issue_records.each_slice(GithubSyncCoordinator::BATCH_SIZE) do |batch|
          Rails.logger.debug "Persisting batch of #{batch.size} issues"
          GithubIssue.upsert_all(batch, unique_by: [:owner_name, :repository_name, :issue_number])
        end
      end

      true
    end

    private
      def fetch_existing_issue_data(api_returned_issues)
        issue_numbers = api_returned_issues.map(&:number)
        owner_name, repository_name = @repository.split("/")

        GithubIssue.where(
          owner_name:,
          repository_name:,
          issue_number: issue_numbers
        ).pluck(:issue_number, :issue_updated_at).to_h
      end

      def select_new_or_updated_issues(api_returned_issues, existing_issues_data)
        api_returned_issues.select do |api_returned_issue|
          existing_record_issue_updated_at = existing_issues_data[api_returned_issue.number]
          existing_record_issue_updated_at.nil? || existing_record_issue_updated_at < api_returned_issue.updated_at
        end
      end
  end
end
