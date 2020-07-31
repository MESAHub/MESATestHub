class AddRelationCountersForCommits < ActiveRecord::Migration[5.2]
  def change
    add_column :commits, :children_count, :integer, default: 0
    add_column :commits, :parents_count, :integer, default: 0
  end
end
