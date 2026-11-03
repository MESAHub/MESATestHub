namespace :branches do
  desc "Catch up on missed webhook pushes by reconciling local branch " \
       "heads with GitHub's branch list. One api.branches call + one " \
       "api.compare per moved branch. Safe to run any time; idempotent."
  task sync: :environment do
    puts "Reconciling local branches with GitHub..."
    stats = Branch.reconcile_with_github
    puts "  created:   #{stats[:created]}"
    puts "  moved:     #{stats[:moved]}"
    puts "  deleted:   #{stats[:deleted]}"
    puts "  unchanged: #{stats[:unchanged]}"
  end
end

namespace :branches do
  desc "Take commits that force-pushes dropped off their branches before " \
       "BranchSyncJob handled force-pushes, recording where each went. " \
       "Dry run unless APPLY=1. SINCE=<days> (default 60) limits it to " \
       "recently ingested commits; BRANCH=<name> limits it to one branch. " \
       "main is skipped: its unreachable members are 2020-21 history with " \
       "missing edges, not rewrites."
  task prune_rewritten: :environment do
    since = (ENV['SINCE'] || 60).to_i.days.ago
    apply = ENV['APPLY'] == '1'
    branches = Branch.where.not(name: 'main').where.not(head_id: nil).order(:name)
    branches = branches.where(name: ENV['BRANCH']) if ENV['BRANCH'].present?

    puts apply ? "Pruning rewritten commits..." : "Dry run (APPLY=1 to write):"
    total = paired_total = 0
    branches.each do |branch|
      dropped = branch.unreachable_member_ids(since: since)
      next if dropped.empty?

      # Replacements are reachable commits ingested in the same window.
      candidates = branch.ordered_commits.where('commits.created_at >= ?', since).pluck(:id)
      pairs = CommitRewrite.pair(Commit.where(id: dropped).to_a,
                                 Commit.where(id: candidates - dropped).to_a)
      puts format('  %-50s %4d dropped, %4d paired', branch.name, dropped.size, pairs.size)
      total += dropped.size
      paired_total += pairs.size
      next unless apply

      branch.record_rewrite(dropped_ids: dropped, candidate_ids: candidates,
                            at: Commit.where(id: candidates).maximum(:created_at) || Time.current)
    end
    puts "  #{total} dropped, #{paired_total} paired#{apply ? '' : ' (nothing written)'}"
  end
end
