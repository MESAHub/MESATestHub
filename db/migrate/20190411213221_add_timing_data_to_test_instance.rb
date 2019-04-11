class AddTimingDataToTestInstance < ActiveRecord::Migration[5.1]
  def change
    add_column :test_instances, :rn_time, :integer
    add_column :test_instances, :re_time, :integer
    add_column :test_instances, :rn_mem, :integer
    add_column :test_instances, :re_mem, :integer
  end
end
