namespace :topology do
  desc "One-time catch-up: populate commit_relations for every branch by " \
       "re-walking GitHub. Idempotent."
  task backfill: :environment do
    branches = Branch.order(:name)
    total = branches.count
    puts "Backfilling commit topology for #{total} branches..."

    branches.find_each.with_index(1) do |branch, i|
      before = CommitRelation.count
      BranchBackfillJob.new.perform(branch.id)
      added = CommitRelation.count - before
      puts "  [#{i}/#{total}] #{branch.name}: +#{added} edges"
    end

    puts "Done. Total edges in commit_relations: #{CommitRelation.count}"
  end
end
