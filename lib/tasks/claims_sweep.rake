# Sweep pending claims past their `expires_at` to `expired`.
# Phase B of docs/dispatcher-and-claims.md. Cheap: a single
# indexed UPDATE backed by `index_claims_on_expires_at_pending`
# (a partial index on expires_at, scoped to `status = 'pending'`).
#
# Production runs this via the `claim_sweep` Solid Queue recurring
# task (ClaimSweeperJob, config/recurring.yml). The rake task stays
# for manual runs:
#   bundle exec rake claims:sweep
#
# The `expired → fulfilled` reverse transition (legitimate late
# submission) is handled by the Submission after_create_commit
# callback on Submission, not here — this task only forward-
# transitions pending → expired.
namespace :claims do
  desc 'Mark pending claims past their expires_at as expired.'
  task sweep: :environment do
    now = Time.current
    n = Claim.sweep_expired!(now: now)
    puts "Swept #{n} expired claim(s) at #{now.iso8601}."
  end
end

namespace :claims do
  # Phase C of docs/dispatcher-and-claims.md. Submissions refresh
  # `commits.<config>_satisfied_at` as they arrive; this fills the
  # columns in for commits whose results landed before that callback
  # existed. Safe to re-run — it only ever sets unset columns.
  desc 'Backfill [ci optional]/[ci fpe]/[ci converge] satisfaction on flagged commits.'
  task backfill_satisfaction: :environment do
    scope = Commit.where('wants_full_inlists OR wants_fpe OR wants_converge')
    scope.find_each(&:refresh_ci_satisfaction!)
    puts "Checked #{scope.count} flagged commit(s)."
  end
end
