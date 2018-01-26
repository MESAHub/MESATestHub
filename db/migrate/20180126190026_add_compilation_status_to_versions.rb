class AddCompilationStatusToVersions < ActiveRecord::Migration[5.1]
  def up
    add_column :versions, :compilation_status, :integer
  end

  def down
    remove_column :versions, :compilation_status
  end
end
