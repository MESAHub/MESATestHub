# Sweep pending claims past their `expires_at` to `expired`.
# Phase B of docs/dispatcher-and-claims.md. Cheap: a single
# indexed UPDATE backed by `index_claims_on_expires_at_pending`
# (a partial index on expires_at, scoped to `status = 'pending'`).
#
# Run from Railway cron every ~5 minutes:
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
