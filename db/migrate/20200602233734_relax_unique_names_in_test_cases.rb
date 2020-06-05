class RelaxUniqueNamesInTestCases < ActiveRecord::Migration[5.1]
  def change
    remove_index :test_cases, :name
    add_index :test_cases, [:name, :module]
  end
end
