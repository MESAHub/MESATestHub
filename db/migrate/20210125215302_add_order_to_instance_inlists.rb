class AddOrderToInstanceInlists < ActiveRecord::Migration[6.0]
  def change
    add_column :instance_inlists, :order, :integer, default: 0
  end
end
