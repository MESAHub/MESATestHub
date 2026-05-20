namespace :test_cases do
  desc "Populate TestCaseCommit rows for any commits that have none. " \
       "Copies from parent commit when possible, falls back to fetching " \
       "do1_test_source from GitHub. Idempotent."
  task populate: :environment do
    bad = Commit.where(test_case_count: 0)
    total = bad.count
    puts "Found #{total} commits without test cases. Populating..."

    copied, fetched, skipped = 0, 0, 0

    bad.find_each.with_index(1) do |commit, i|
      result = Commit.populate_test_cases_for(commit)
      commit.reload
      case result
      when :copied  then copied  += 1
      when :fetched then fetched += 1
      else               skipped += 1
      end
      puts "  [#{i}/#{total}] #{commit.short_sha}: #{result} " \
           "→ #{commit.test_case_count} tests"
    end

    puts ""
    puts "Done. copied: #{copied}, fetched: #{fetched}, skipped: #{skipped}"
  end
end
