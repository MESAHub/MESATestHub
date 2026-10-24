# Re-read the `[ci ...]` directives from every commit's message
# (CommitMessageFlags), e.g. after the parser learns something new --
# like `[ci converge 0.5]`, which it didn't recognize at all before
# Oct 2026. Only commits whose flags change are touched. A commit whose
# converge request changes gets its converge satisfaction recomputed,
# since a named factor changes which runs count.
#
#   bundle exec rake commits:reparse_ci_flags
namespace :commits do
  desc 'Re-parse [ci ...] directives from commit messages and update changed commits.'
  task reparse_ci_flags: :environment do
    changed = 0
    Commit.find_each do |commit|
      flags = CommitMessageFlags.parse(commit.message)
      next if flags.all? { |col, value| commit[col] == value }

      converge_changed = commit.wants_converge != flags[:wants_converge] ||
                         commit.converge_factor != flags[:converge_factor]
      attrs = flags.dup
      attrs[:converge_satisfied_at] = nil if converge_changed
      commit.update_columns(attrs)
      commit.refresh_ci_satisfaction! if converge_changed
      changed += 1
    end
    puts "Updated CI flags on #{changed} commit(s)."
  end
end
