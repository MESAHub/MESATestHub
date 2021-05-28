class AddCpuHoursToTestInstances < ActiveRecord::Migration[6.0]
  def change
    add_column :test_instances, :cpu_hours, :float, default: 0
  end
end
