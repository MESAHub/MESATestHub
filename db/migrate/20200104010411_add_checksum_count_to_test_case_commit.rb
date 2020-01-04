class AddChecksumCountToTestCaseCommit < ActiveRecord::Migration[5.1]
  def change
    add_column :test_case_commits, :checksum_count, :integer, default: 0
    change_column_default :test_case_commits, :submission_count, from: nil, to: 0
    change_column_default :test_case_commits, :computer_count, from: nil, to: 0
    change_column_default :test_case_commits, :status, from: nil, to: -1
    change_column_null :test_case_commits, :commit_id, false
    change_column_null :test_case_commits, :test_case_id, false
  end
end
