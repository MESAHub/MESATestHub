# A commit that a force-push (usually a rebase) dropped from a branch,
# and the commit that replaced it there when one can be identified.
# Written by Branch#record_rewrite; read by the commit pages to explain
# a SHA that's no longer on its branch, and to show a rebased commit's
# results from before the rebase.
class CommitRewrite < ApplicationRecord
  belongs_to :branch
  belongs_to :old_commit, class_name: 'Commit'
  belongs_to :new_commit, class_name: 'Commit', optional: true

  # How far back to follow a commit rebased more than once.
  CHAIN_LIMIT = 10

  # Pair each dropped commit with its replacement. A rebase keeps the
  # author and message (and author date), and changes the SHA and the
  # committer date. Returns { old_id => new_id }, leaving out commits
  # with no match or more than one (a reworded commit, or two "fix"
  # commits nothing tells apart). Author date breaks ties only when
  # both sides have it; commits ingested before Nov 2026 don't.
  #
  # Several old commits may pair with one new commit: a branch rebased
  # three times before this ran drops three versions of each commit at
  # once, and all of them are earlier versions of the current one.
  def self.pair(old_commits, new_commits)
    by_key = new_commits.group_by { |c| [c.author_email, c.message] }
    old_commits.each_with_object({}) do |old, pairs|
      candidates = by_key.fetch([old.author_email, old.message], [])
      if candidates.size > 1 && old.author_time
        candidates = candidates.select { |c| c.author_time == old.author_time }
      end
      pairs[old.id] = candidates.first.id if candidates.size == 1
    end
  end

  # The commits `commit` replaced, nearest first: its predecessor, that
  # commit's predecessor, and so on (a branch rebased several times).
  def self.predecessors_of(commit)
    chain = []
    current_ids = [commit.id]
    seen = Set[commit.id]
    CHAIN_LIMIT.times do
      # Newest version first: ingest time orders versions dropped together.
      rows = where(new_commit_id: current_ids).includes(:old_commit, :branch).to_a
      rows.reject! { |r| seen.include?(r.old_commit_id) }
      rows.uniq!(&:old_commit_id) # the same SHA dropped from several branches
      rows.sort_by! { |r| [-r.rewritten_at.to_f, -r.old_commit.created_at.to_f] }
      break if rows.empty?

      chain.concat(rows)
      seen.merge(rows.map(&:old_commit_id))
      current_ids = rows.map(&:old_commit_id)
    end
    chain
  end
end
