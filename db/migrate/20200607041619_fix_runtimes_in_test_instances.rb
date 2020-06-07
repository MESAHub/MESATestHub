class FixRuntimesInTestInstances < ActiveRecord::Migration[5.1]
  def change
    change_column :test_instances, :runtime_seconds, :integer, null: true
    add_column :test_instances, :newton_iters, :integer
    add_column :test_instances, :newton_retries, :integer
  end
end
