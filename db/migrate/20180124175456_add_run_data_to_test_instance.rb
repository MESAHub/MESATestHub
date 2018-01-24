class AddRunDataToTestInstance < ActiveRecord::Migration[5.1]
  def up
    add_column :test_instances, :steps, :integer
    add_column :test_instances, :retries, :integer
    add_column :test_instances, :backups, :integer
  end

  def down
    remove_column :test_instances, :steps
    remove_column :test_instances, :retries
    remove_column :test_instances, :backups
  end
end
