namespace :commits do
  desc "Backfill commits.commit_time with the committer date for " \
       "commits on every branch within the last N days (default 90). " \
       "Historical data stored the author date here, which disagrees " \
       "with the committer date for any commit applied via " \
       "rebase-and-merge, squash-and-merge, or amend — and that's the " \
       "ordering that puts the branch head at the top of every list. " \
       "Idempotent: only writes rows whose stored value actually differs."
  task :backfill_commit_time, [:days] => :environment do |_, args|
    days_back = (args[:days] || 90).to_i
    since_iso = days_back.days.ago.utc.iso8601

    branches = Branch.order(:name)
    puts "Backfilling commit_time from committer date for " \
         "#{branches.count} branches (since #{since_iso})..."

    total_checked = 0
    total_updated = 0

    branches.find_each.with_index(1) do |branch, i|
      gh_commits = Commit.api_commits(sha: branch.name, since: since_iso)
      if gh_commits.nil?
        puts "  [#{i}] #{branch.name}: branch missing on GitHub, skipping"
        next
      end

      # Build sha -> committer_date map. Sawyer::Resource responds to
      # `[:foo]` lookup the same way as a plain Hash, so this works for
      # both real API responses and stubbed test fixtures.
      gh_dates = gh_commits.each_with_object({}) do |gh, map|
        date = gh[:commit][:committer][:date]
        # Octokit hands us strings here; Postgres-backed Time
        # comparisons want a Time.
        map[gh[:sha]] = date.is_a?(String) ? Time.zone.parse(date) : date
      end

      checked = gh_dates.size
      updated = 0

      Commit.where(sha: gh_dates.keys)
            .find_each do |commit|
        new_time = gh_dates[commit.sha]
        next if new_time.nil?
        # Database stores microsecond precision; compare with tolerance
        # so identical-but-different-precision values don't churn.
        next if commit.commit_time && (commit.commit_time - new_time).abs < 1.0

        commit.update_columns(commit_time: new_time)
        updated += 1
      end

      total_checked += checked
      total_updated += updated
      puts "  [#{i}] #{branch.name}: checked #{checked}, updated #{updated}"
    end

    puts ""
    puts "Done. checked=#{total_checked} updated=#{total_updated}"
  end
end
