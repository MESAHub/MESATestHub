class CreateTestCaseCommits < ActiveRecord::Migration[5.1]
  def change
    create_table :test_case_commits do |t|
      t.integer :status
      t.integer :submission_count
      t.integer :computer_count
      t.datetime :last_tested
      t.references :commit, foreign_key: true
      t.references :test_case, foreign_key: true

      t.timestamps
    end
  end
end
