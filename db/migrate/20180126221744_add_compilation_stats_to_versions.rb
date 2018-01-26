class AddCompilationStatsToVersions < ActiveRecord::Migration[5.1]
  def up
    add_column :versions, :compile_success_count, :integer, default: 0
    add_column :versions, :compile_fail_count, :integer, default: 0
  end
  def down
    remove_column :versions, :compile_success_count
    remove_column :versions, :compile_fail_count
  end
end
