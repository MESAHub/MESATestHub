class AddTestCaseCommitToTestInstance < ActiveRecord::Migration[5.1]
  def change
    add_reference :test_instances, :test_case_commit
  end
end
