class RemoveBogusStringFromInstanceInlists < ActiveRecord::Migration[5.1]
  def change
    remove_column :instance_inlists, :integer
  end
end
