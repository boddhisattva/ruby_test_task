# frozen_string_literal: true

# == Schema Information
#
# Table name: repository_stats
#
#  id                                                            :bigint           not null, primary key
#  owner_name(The owner of the repository)                       :string           not null
#  provider(Provider name (e.g., 'github'))                      :string           not null
#  repository_name(The name of the repository)                   :string           not null
#  total_issues_count(Total issues count for a given repository) :integer          default(0), not null
#  created_at                                                    :datetime         not null
#  updated_at                                                    :datetime         not null
#
# Indexes
#
#  idx_repository_stats_unique  (provider,owner_name,repository_name) UNIQUE
#
class RepositoryStat < ApplicationRecord
  validates :provider, :owner_name, :repository_name, presence: true
  validates :provider, uniqueness: { scope: [:owner_name, :repository_name] }

  def self.fetch_cached(provider, owner, repo)
    Rails.cache.fetch("repo_stat/#{provider}/#{owner}/#{repo}", expires_in: 5.minutes) do
      find_by(provider:, owner_name: owner, repository_name: repo)
    end
  end

  def update_total_count!
    execute_count_update_sql
    reload
  end

  private
    def execute_count_update_sql
      self.class.connection.execute(count_update_sql)
    end

    def count_update_sql
      <<-SQL.squish
      UPDATE repository_stats
      SET total_issues_count = #{count_subquery},
      updated_at = CURRENT_TIMESTAMP
      WHERE id = #{id}
      SQL
    end

    def count_subquery
      <<-SQL.squish
      COALESCE((
        SELECT COUNT(*)
        FROM github_issues
        WHERE owner_name = #{quoted_owner_name}
        AND repository_name = #{quoted_repository_name}
      ), 0)
      SQL
    end

    def quoted_owner_name
      "'#{self.class.connection.quote_string(owner_name)}'"
    end

    def quoted_repository_name
      "'#{self.class.connection.quote_string(repository_name)}'"
    end

    after_commit :clear_cache

    def clear_cache
      Rails.cache.delete("repo_stat/#{provider}/#{owner_name}/#{repository_name}")
    end
end
