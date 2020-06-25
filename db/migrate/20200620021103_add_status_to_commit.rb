class AddStatusToCommit < ActiveRecord::Migration[5.1]
  def change
    add_column :commits, :status, :integer, default: 0
  end
end
