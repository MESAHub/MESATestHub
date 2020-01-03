class CreateCommits < ActiveRecord::Migration[5.1]
  def change
    create_table :commits do |t|
      t.string :sha, null: false, unique: true
      t.string :author, null: false
      t.string :author_email, null: false
      t.text :message, null: false
      t.datetime :commit_time, null: false

      t.timestamps

      t.index :sha, unique: true
    end
  end
end
