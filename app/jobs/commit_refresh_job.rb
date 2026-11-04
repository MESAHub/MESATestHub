# Recomputes a commit's stored scalars: the counts and statuses on its
# stale TestCaseCommits, then the commit's own (Commit#update_scalars),
# then CI-request satisfaction. Submissions used to do this inline, once
# per result: each test's scalars twice (TestInstance#update_tcc, then
# Submission#update_commit) and the commit's twice (an explicit
# update_scalars plus the before_save that runs it again), ~40-55
# queries in the request. With one submission per test result, a busy
# commit got 30+ of these a minute during a run, each redoing the last.
#
# Commit.mark_scalars_stale flags the work and enqueues this job only
# when the commit's flag flips, delayed by DELAY, so a burst of results
# collapses into one refresh every few seconds. The job clears flags
# BEFORE reading: a result committed after a clear flips the flag again
# and enqueues another run; one committed before it is visible to the
# reads that follow. Nothing is lost between runs.
#
# The matrix, rings, and pills don't read these scalars (they're built
# from test_instances; see CommitState), so a page shows new results
# right away. The stored counts (index meta line, test-case history,
# the morning digest) lag by up to DELAY.
class CommitRefreshJob < ApplicationJob
  queue_as :default

  DELAY = 5.seconds

  # Runs for the same commit queue up rather than overlap. Overlap would
  # still be correct, just wasted work.
  limits_concurrency to: 1, key: ->(commit_id) { "commit_refresh_#{commit_id}" }, duration: 5.minutes

  def perform(commit_id)
    commit = Commit.find_by(id: commit_id)
    return unless commit

    Commit.where(id: commit_id).update_all(scalars_dirty: false)
    tcc_ids = TestCaseCommit.connection.select_values(TestCaseCommit.sanitize_sql([<<~SQL.squish, commit_id]))
      UPDATE test_case_commits SET needs_refresh = false
       WHERE commit_id = ? AND needs_refresh RETURNING id
    SQL
    begin
      TestCaseCommit.where(id: tcc_ids).find_each(&:update_and_save_scalars)

      # Commit's before_save runs update_scalars, after the TCCs above
      # since it counts their statuses.
      commit.save
      commit.refresh_ci_satisfaction!
    rescue StandardError
      # Put the flags back so the work isn't lost: the next result's
      # mark, or the stale_scalars sweep (config/recurring.yml), retries.
      TestCaseCommit.where(id: tcc_ids).update_all(needs_refresh: true)
      Commit.where(id: commit_id).update_all(scalars_dirty: true)
      raise
    end
  end

  # Backstop for refreshes that never ran: a failed job, or an enqueue
  # lost after the flag flipped. Fired from config/recurring.yml.
  def self.sweep_stale
    Commit.where(scalars_dirty: true).pluck(:id).each { |id| perform_later(id) }
  end
end
