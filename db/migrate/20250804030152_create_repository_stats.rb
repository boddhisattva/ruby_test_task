# frozen_string_literal: true

class CreateRepositoryStats < ActiveRecord::Migration[7.1]
  def change
    create_table :repository_stats do |t|
      t.string :provider, null: false, comment: "Provider name (e.g., 'github')"
      t.string :owner_name, null: false, comment: "The owner of the repository"
      t.string :repository_name, null: false, comment: "The name of the repository"
      t.integer :total_issues_count, default: 0, null: false, comment: "Total issues count for a given repository"

      t.timestamps
    end

    add_index :repository_stats,
              [:provider, :owner_name, :repository_name],
              unique: true,
              name: "idx_repository_stats_unique"
  end
end
