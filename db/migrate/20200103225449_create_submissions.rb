class CreateSubmissions < ActiveRecord::Migration[5.1]
  def change
    create_table :submissions do |t|
      t.boolean :compiled
      t.boolean :entire
      t.references :commit, foreign_key: true
      t.references :computer, foreign_key: true

      t.timestamps
    end
  end
end
