class RemoveHeadIndexOnBranches < ActiveRecord::Migration[5.1]
  def change
    remove_index :branches, :head_id
  end
end
