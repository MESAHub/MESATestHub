class UpdateMemNames < ActiveRecord::Migration[5.1]
  def change
    rename_column :test_instances, :rn_mem, :mem_rn
    rename_column :test_instances, :re_mem, :mem_re
  end
end
