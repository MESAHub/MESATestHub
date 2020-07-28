class CreateBranches < ActiveRecord::Migration[5.1]
  def change
    create_table :branches do |t|
      t.string :name, null: false
      t.boolean :merged, default: false
      t.references :head, foreign_key: { to_table: :commits }

      t.timestamps
    end
    add_index :branches, :name, unique: true
  end
end
