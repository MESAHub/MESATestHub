class AddComputerInfoToTestInstances < ActiveRecord::Migration[5.1]
  def up
    add_column :test_instances, :computer_name, :string
    add_column :test_instances, :computer_specification, :string
  end
  def down
    remove_column :test_instances, :computer_name
    remove_column :test_instances, :computer_specification
  end

end
