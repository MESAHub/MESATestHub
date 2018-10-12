class TweakTestCaseVersion < ActiveRecord::Migration[5.1]
  def up
    rename_column :test_case_versions, :computers, :computer_count
    rename_column :test_case_versions, :submissions, :submission_count
  end

  def down
    rename_column :test_case_versions, :computer_count, :computers
    rename_column :test_case_versions, :submission_count, :submissions
  end
end
