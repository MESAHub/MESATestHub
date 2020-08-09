class AddRunOptionalToInstances < ActiveRecord::Migration[5.2]
  def change
    add_column :test_instances, :run_optional, :boolean
  end
end
