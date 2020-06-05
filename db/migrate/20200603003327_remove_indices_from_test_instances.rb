class RemoveIndicesFromTestInstances < ActiveRecord::Migration[5.1]
  def change
    remove_index :test_instances, :test_case_version_id
    remove_index :test_instances, :version_id
  end
end
