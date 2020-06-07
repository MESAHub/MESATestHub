class UpdateInstances < ActiveRecord::Migration[5.1]
  def change
    add_column :test_instances, :sdk_version, :string
    add_column :test_instances, :math_backend, :string
    add_column :test_instances, :runtime_minutes, :float
    add_column :submissions, :compiler, :string
    add_column :submissions, :compiler_version, :string
    add_column :submissions, :sdk_version, :string
    add_column :submissions, :math_backend, :string
  end
end
