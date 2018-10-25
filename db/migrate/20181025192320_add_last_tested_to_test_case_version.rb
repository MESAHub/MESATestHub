class AddLastTestedToTestCaseVersion < ActiveRecord::Migration[5.1]
  def up
    add_column :test_case_versions, :last_tested, :datetime
  end
  def down
    remove_column :test_case_versions, :last_tested
  end
end
