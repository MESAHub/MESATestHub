class CreateCommitRelations < ActiveRecord::Migration[5.1]
  def change
    create_table :commit_relations do |t|
      t.references :child, foreign_key: { to_table: :commits }
      t.references :parent, foreign_key: { to_table: :commits }
      t.timestamps
    end
  end
end
