class AddScalarsToInlists < ActiveRecord::Migration[6.0]
  def change
    add_column :instance_inlists, :model_number, :integer, default: -1
    add_column :instance_inlists, :star_age, :float, default: -1.0
    add_column :instance_inlists, :num_retries, :integer, default: -1
  end
end
