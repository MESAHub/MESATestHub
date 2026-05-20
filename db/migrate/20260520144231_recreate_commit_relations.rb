class RecreateCommitRelations < ActiveRecord::Migration[8.0]
  def change
    create_table :commit_relations do |t|
      t.bigint :parent_id, null: false
      t.bigint :child_id,  null: false
      # 0 for the first parent (almost every commit). Merge commits use
      # 1..N for the remaining parents, so a first-parent walk is
      # `WHERE parent_index = 0`.
      t.integer :parent_index, null: false, default: 0
    end

    add_index :commit_relations, [:child_id, :parent_id], unique: true
    add_index :commit_relations, :parent_id

    add_foreign_key :commit_relations, :commits, column: :parent_id
    add_foreign_key :commit_relations, :commits, column: :child_id
  end
end
