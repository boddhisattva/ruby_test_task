# frozen_string_literal: true

module GithubSync
  class IssuePersister
    def initialize(repository)
      @repository = repository
    end

    def persist(api_returned_issues)
      return false if api_returned_issues.empty?

      new_or_updated_issues_to_be_persisted = find_changed_issues(api_returned_issues)
      return false if new_or_updated_issues_to_be_persisted.empty?

      persist_changed_issues(new_or_updated_issues_to_be_persisted)

      true
    end

    private
      def find_changed_issues(api_returned_issues)
        existing_issues_data = fetch_existing_issue_data(api_returned_issues)
        select_new_or_updated_issues(api_returned_issues, existing_issues_data)
      end

      def persist_changed_issues(issues)
        ActiveRecord::Base.transaction do
          issue_records = prepare_issue_records(issues)
          persist_in_batches(issue_records)
        end
      end

      def prepare_issue_records(issues)
        user_id_map = process_users_for_issues(issues)
        build_issue_records(issues, user_id_map)
      end

      def process_users_for_issues(issues)
        user_processor = UserProcessor.new
        user_processor.process_users(issues)
      end

      def build_issue_records(issues, user_id_map)
        issue_builder = IssueBuilder.new(@repository, user_id_map)
        issue_builder.build_records(issues)
      end

      def persist_in_batches(issue_records)
        issue_records.each_slice(GithubSyncCoordinator::BATCH_SIZE) do |batch|
          Rails.logger.debug "Persisting batch of #{batch.size} issues"
          GithubIssue.upsert_all(batch, unique_by: [:owner_name, :repository_name, :issue_number])
        end
      end

      def fetch_existing_issue_data(issues)
        issue_numbers = issues.map(&:number)
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
