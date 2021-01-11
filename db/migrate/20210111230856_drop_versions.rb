class DropVersions < ActiveRecord::Migration[6.0]
  def change
    remove_index :test_instances, name: 'index_test_instances_on_mesa_version'
    remove_column :test_instances, :test_case_version_id
    remove_column :test_instances, :mesa_version
    remove_column :test_instances, :version_id
    remove_column :test_cases, :version_id
    remove_column :test_cases, :version_added
    drop_table :test_case_versions
    drop_table :versions
  end
end
