class AddShortShaToCommit < ActiveRecord::Migration[5.1]
  def change
    add_column :commits, :short_sha, :string, unique: true, index: true
  end
end
