class CreateInlistData < ActiveRecord::Migration[5.1]
  def change
    create_table :inlist_data do |t|
      t.string :name
      t.float :val
      t.references :instance_inlist, foreign_key: true, index: true

      t.timestamps
    end
  end
end
