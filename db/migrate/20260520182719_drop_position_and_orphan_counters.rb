class DropPositionAndOrphanCounters < ActiveRecord::Migration[8.0]
  def change
    # branch_memberships.position drove the old ordering scheme.
    # Phase 3.5's recursive CTE over commit_relations replaces it
    # entirely (Branch#ordered_commits), and the only writers were
    # api_update / api_reorder_* which were deleted in the previous
    # commit.
    remove_column :branch_memberships, :position, :integer

    # commits.parents_count and commits.children_count were counter
    # caches for the *original* (2020, later-dropped) commit_relations
    # table. They've sat at default 0 since the 2021 drop and nothing
    # reads them now — the only readers were Commit.root / Branch#root,
    # which were just deleted. If we ever want counter caches on the
    # current CommitRelation, we can add them back as a small additive
    # change.
    remove_column :commits, :parents_count, :integer, default: 0
    remove_column :commits, :children_count, :integer, default: 0
  end
end
