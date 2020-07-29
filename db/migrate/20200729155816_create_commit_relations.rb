class CreateCommitRelations < ActiveRecord::Migration[5.1]
  def change
    create_table :commit_relations do |t|

      t.timestamps
    end
  end
end
