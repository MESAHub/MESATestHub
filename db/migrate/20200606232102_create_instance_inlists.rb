class CreateInstanceInlists < ActiveRecord::Migration[5.1]
  def change
    create_table :instance_inlists do |t|
      t.string :inlist_name
      t.float :runtime_minutes
      t.integer :retries
      t.integer :steps
      t.string :newton_retries
      t.string :integer
      t.integer :newton_iters
      t.references :test_instance, foreign_key: true, index: true

      t.timestamps
    end
  end
end
