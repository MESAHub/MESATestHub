class AddFpeChecksToTestInstances < ActiveRecord::Migration[5.2]
  def change
    add_column :test_instances, :fpe_checks, :boolean
  end
end
