class AddSummaryTextToTestInstances < ActiveRecord::Migration[5.1]
  def up
    add_column :test_instances, :summary_text, :text
  end

  def down
    remove_column :test_instances, :summary_text
  end
end
