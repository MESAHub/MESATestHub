class AddTrackersToCommits < ActiveRecord::Migration[5.1]
  def change
    add_column :commits, :test_case_count, :integer, default: 0
    add_column :commits, :passed_count, :integer, default: 0
    add_column :commits, :failed_count, :integer, default: 0
    add_column :commits, :mixed_count, :integer, default: 0
    add_column :commits, :untested_count, :integer, default: 0
    add_column :commits, :checksum_count, :integer, default: 0
    add_column :commits, :complete_computer_count, :integer, default: 0
    add_column :commits, :computer_count, :integer, default: 0

    add_index :commits, :short_sha, unique: :true
  end
end
