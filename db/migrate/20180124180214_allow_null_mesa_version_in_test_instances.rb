class AllowNullMesaVersionInTestInstances < ActiveRecord::Migration[5.1]
  def up
    change_column :test_instances, :mesa_version, :integer, null: true
  end

  def down
    change_column :test_instances, :mesa_version, :integer, null: false
  end  
end
