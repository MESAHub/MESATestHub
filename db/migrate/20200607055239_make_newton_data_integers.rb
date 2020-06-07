class MakeNewtonDataIntegers < ActiveRecord::Migration[5.1]
  def change
    remove_column :instance_inlists, :newton_retries
    remove_column :instance_inlists, :newton_iters
    add_column :instance_inlists, :newton_retries, :integer
    add_column :instance_inlists, :newton_iters, :integer
  end
end
