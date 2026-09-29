# TestCaseCommit had no unique index on (commit_id, test_case_id), and
# its creation paths check-then-insert. Two sync jobs populating the
# same commit at once (e.g. a webhook's BranchSyncJob racing the
# periodic BranchReconcileJob) each saw no rows and each inserted a full
# set — e87d3be (brent, 2026-09-24) got 214 TCCs for 107 tests, plus a
# handful of 2021 commits. Instances then attached to either copy, and
# the commit matrix (one TCC per test) read whichever came last, so
# results showed under the wrong computers or not at all.
#
# Merge every duplicate group into its oldest row (moving instances and
# claims), delete the extras, recompute the survivors' scalars and their
# commits', then add the unique index so it can't recur.
class DedupeTestCaseCommitsAndAddUniqueIndex < ActiveRecord::Migration[8.0]
  def up
    execute <<~SQL
      CREATE TEMP TABLE tcc_dupes ON COMMIT DROP AS
      SELECT id, keeper_id FROM (
        SELECT id, MIN(id) OVER (PARTITION BY commit_id, test_case_id) AS keeper_id
        FROM test_case_commits
      ) t
      WHERE id <> keeper_id
    SQL

    keeper_ids = select_values("SELECT DISTINCT keeper_id FROM tcc_dupes")

    execute <<~SQL
      UPDATE test_instances ti SET test_case_commit_id = d.keeper_id
      FROM tcc_dupes d WHERE ti.test_case_commit_id = d.id
    SQL
    execute <<~SQL
      UPDATE claims c SET test_case_commit_id = d.keeper_id
      FROM tcc_dupes d WHERE c.test_case_commit_id = d.id
    SQL
    execute "DELETE FROM test_case_commits WHERE id IN (SELECT id FROM tcc_dupes)"

    add_index :test_case_commits, %i[commit_id test_case_id], unique: true,
              name: 'index_test_case_commits_on_commit_id_and_test_case_id'

    # Survivors picked up instances from their duplicates, so their
    # stored status/counts are stale; so are their commits' scalars.
    TestCaseCommit.reset_column_information
    Commit.reset_column_information
    commit_ids = TestCaseCommit.where(id: keeper_ids).distinct.pluck(:commit_id)
    TestCaseCommit.where(id: keeper_ids).find_each(&:update_and_save_scalars)
    Commit.where(id: commit_ids).find_each do |commit|
      commit.update_scalars
      commit.save(validate: false)
    end
  end

  def down
    remove_index :test_case_commits, name: 'index_test_case_commits_on_commit_id_and_test_case_id'
  end
end
