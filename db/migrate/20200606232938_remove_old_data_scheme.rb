class RemoveOldDataScheme < ActiveRecord::Migration[5.1]
  def change
    drop_table :test_data
    remove_column :test_cases, :datum_1_name
    remove_column :test_cases, :datum_2_name
    remove_column :test_cases, :datum_3_name
    remove_column :test_cases, :datum_4_name
    remove_column :test_cases, :datum_5_name
    remove_column :test_cases, :datum_6_name
    remove_column :test_cases, :datum_7_name
    remove_column :test_cases, :datum_8_name
    remove_column :test_cases, :datum_9_name
    remove_column :test_cases, :datum_10_name
    remove_column :test_cases, :datum_1_type
    remove_column :test_cases, :datum_2_type
    remove_column :test_cases, :datum_3_type
    remove_column :test_cases, :datum_4_type
    remove_column :test_cases, :datum_5_type
    remove_column :test_cases, :datum_6_type
    remove_column :test_cases, :datum_7_type
    remove_column :test_cases, :datum_8_type
    remove_column :test_cases, :datum_9_type
    remove_column :test_cases, :datum_10_type
  end
end
