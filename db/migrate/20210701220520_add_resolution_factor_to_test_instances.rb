class AddResolutionFactorToTestInstances < ActiveRecord::Migration[6.0]
  def change
    add_column :test_instances, :resolution_factor, :float, default: 1
  end
end
