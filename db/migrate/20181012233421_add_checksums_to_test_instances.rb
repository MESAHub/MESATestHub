class AddChecksumsToTestInstances < ActiveRecord::Migration[5.1]
  def up
    add_column :test_instances, :checksum, :string
  end
  def down
    remove_column :test_instances, :checksum
  end
end
