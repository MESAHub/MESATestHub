class AllowNullVersionCreated < ActiveRecord::Migration[5.1]
  def change
    remove_index :test_cases, name: 'index_test_cases_on_version_id'
  end
end
