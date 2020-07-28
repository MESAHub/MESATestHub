class CreateBranches < ActiveRecord::Migration[5.1]
  def change
    create_table :branches do |t|
      t.string :name
      t.bool :merged

      t.timestamps
    end
    add_index :branches, :name, unique: true
  end
end
