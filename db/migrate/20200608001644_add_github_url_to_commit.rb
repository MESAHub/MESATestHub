class AddGithubUrlToCommit < ActiveRecord::Migration[5.1]
  def change
    add_column :commits, :github_url, :string
  end
end
