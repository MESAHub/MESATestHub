class AdjustRuntimesInTestInstance < ActiveRecord::Migration[5.1]
  def change
    rename_column :test_instances, :rn_time, :total_runtime_seconds
  end
end
