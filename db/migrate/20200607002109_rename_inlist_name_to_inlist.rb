class RenameInlistNameToInlist < ActiveRecord::Migration[5.1]
  def change
    rename_column :instance_inlists, :inlist_name, :inlist
  end
end
