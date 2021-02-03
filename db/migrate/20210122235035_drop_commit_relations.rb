class DropCommitRelations < ActiveRecord::Migration[6.0]
  def change
    drop_table :commit_relations
  end
end
