class AddCountsToTestCaseCommits < ActiveRecord::Migration[5.2]
  def change
    add_column :test_case_commits, :passed_count, :integer, default: 0
    add_column :test_case_commits, :failed_count, :integer, default: 0
  end
end
