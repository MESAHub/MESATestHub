# One row per commit a force-push (usually a rebase) dropped from a
# branch. new_commit_id is the commit that replaced it on that branch,
# when one can be paired (same author and message); nil when the commit
# was dropped outright or reworded. Lets the commit pages say "rebased
# from abc1234" / "no longer on this branch" instead of 404ing, and
# carry the old SHA's results forward as context.
class CreateCommitRewrites < ActiveRecord::Migration[8.0]
  def change
    create_table :commit_rewrites do |t|
      t.references :branch, null: false, foreign_key: { on_delete: :cascade }
      t.references :old_commit, null: false, foreign_key: { to_table: :commits, on_delete: :cascade }
      t.references :new_commit, foreign_key: { to_table: :commits, on_delete: :nullify }
      # Push endpoints, for reference. before_sha is nil for rewrites
      # found after the fact by `rake branches:prune_rewritten`.
      t.string :before_sha
      t.string :after_sha
      t.datetime :rewritten_at, null: false
      t.timestamps
    end
    add_index :commit_rewrites, %i[branch_id old_commit_id], unique: true
  end
end
