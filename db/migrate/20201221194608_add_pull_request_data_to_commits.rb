class AddPullRequestDataToCommits < ActiveRecord::Migration[5.2]
  def change
    add_column :commits, :pull_request, :boolean, default: false
    add_column :commits, :open, :boolean
  end
end
