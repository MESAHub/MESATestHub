class UpdateInstanceFields < ActiveRecord::Migration[5.1]
  def change
    rename_column :instance_inlists, :newton_iters, :solver_iterations
    rename_column :instance_inlists, :newton_retries, :solver_calls_failed
    add_column :instance_inlists, :solver_calls_made, :integer
    add_column :instance_inlists, :redos, :integer
    add_column :instance_inlists, :log_rel_run_E_err, :float

    rename_column :test_instances, :newton_iters, :solver_iterations
    rename_column :test_instances, :newton_retries, :solver_calls_failed
    add_column :test_instances, :solver_calls_made, :integer
    add_column :test_instances, :redos, :integer
    add_column :test_instances, :log_rel_run_E_err, :float
  end
end
