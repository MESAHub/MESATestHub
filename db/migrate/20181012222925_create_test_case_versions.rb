class CreateTestCaseVersions < ActiveRecord::Migration[5.1]
  def up
    create_table :test_case_versions do |t|
      t.references :version, foreign_key: true, null: false
      t.references :test_case, foreign_key: true, null: false

      t.integer :status, default: -1, null: false
      t.integer :submissions, default: 0, null: false
      t.integer :computers, default:0, null: false
      t.timestamps
    end

    add_reference :test_instances, :test_case_version, foreign_key: true
  end

  def down
    drop_table :test_case_versions
    remove_reference :test_instances, :test_case_version
  end
end
