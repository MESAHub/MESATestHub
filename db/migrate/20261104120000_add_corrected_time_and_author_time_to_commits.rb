# Branch views used to sort by commit_time (the committer date) alone.
# A rebase that keeps old committer dates (EbF/hydro_03_rti_transport,
# Nov 2026) then put the main commit the branch was rebased onto above
# the whole rebased stack. corrected_time is Git's "corrected commit
# date": max(commit_time, latest parent's corrected_time + 1 second).
# It equals commit_time whenever dates follow the history, and it never
# ranks a parent above its child. See Commit.correct_times_from.
#
# author_time (the author date) survives rebases, so it helps pair a
# rebased commit with the commit it replaced. Only commits ingested
# from here on have it; pairing falls back to author + message.
class AddCorrectedTimeAndAuthorTimeToCommits < ActiveRecord::Migration[8.0]
  def up
    add_column :commits, :author_time, :datetime
    add_column :commits, :corrected_time, :datetime

    execute 'UPDATE commits SET corrected_time = commit_time'

    # Bellman-Ford over commit_relations: each round raises every child
    # that sits at or below a parent, then looks only at the children
    # of what moved. The first round scans every edge.
    frontier = nil
    loop do
      filter = frontier ? "WHERE cr.child_id IN (#{frontier.join(',')})" : ''
      moved = select_values(<<~SQL).map(&:to_i)
        UPDATE commits c SET corrected_time = s.t
          FROM (SELECT cr.child_id, MAX(p.corrected_time) + interval '1 second' AS t
                  FROM commit_relations cr
                  JOIN commits p ON p.id = cr.parent_id
                  #{filter}
                 GROUP BY cr.child_id) s
         WHERE c.id = s.child_id AND c.corrected_time < s.t
        RETURNING c.id
      SQL
      break if moved.empty?

      frontier = select_values(
        "SELECT DISTINCT child_id FROM commit_relations WHERE parent_id IN (#{moved.join(',')})"
      ).map(&:to_i)
      break if frontier.empty?
    end

    change_column_null :commits, :corrected_time, false
  end

  def down
    remove_column :commits, :corrected_time
    remove_column :commits, :author_time
  end
end
