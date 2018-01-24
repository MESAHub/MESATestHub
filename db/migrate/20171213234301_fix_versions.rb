class FixVersions < ActiveRecord::Migration[5.1]
  def up
    remove_column :versions, :status
    add_reference :test_instances, :version, foreign_key: true
  end

  def down
    add_column :versions, :status, :integer
    remove_reference :test_instances, :version
  end
end
