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
