# Dirty flags for CommitRefreshJob: a submission marks the TCCs it
# touched and the commit, and the job refreshes and clears them.
# Constant defaults, so on Postgres 11+ neither add_column rewrites its
# table. The job finds a commit's flagged TCCs through the existing
# commit_id index (~100 rows per commit), so no new index.
class AddRefreshFlagsToCommitsAndTccs < ActiveRecord::Migration[8.0]
  def change
    add_column :commits, :scalars_dirty, :boolean, null: false, default: false
    add_column :test_case_commits, :needs_refresh, :boolean, null: false, default: false
  end
end
