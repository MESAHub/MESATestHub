class AddVersionIdToTestCase < ActiveRecord::Migration[5.1]
  def up
    add_reference :test_cases, :version, foreign_key: true
  end

  def down
    remove_reference :test_cases, :version
  end
end
