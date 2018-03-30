class AddDiffToTestInstance < ActiveRecord::Migration[5.1]
  def up
    add_column :test_instances, :diff, :integer, default: 2
  end
  def down
    remove_column :test_instances, :diff
  end
end
