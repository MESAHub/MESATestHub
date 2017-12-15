class CreateVersions < ActiveRecord::Migration[5.1]
  def up
    create_table :versions do |t|
      t.integer :number, null: false
      t.integer :status
      t.string :author
      t.text :log

      t.index :number, unique: true

      t.timestamps
    end
  end

  def down
    drop_table :versions
  end
end
