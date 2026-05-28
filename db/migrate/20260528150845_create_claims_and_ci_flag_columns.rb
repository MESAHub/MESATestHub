# Phase A of the dispatcher + claims feature
# (docs/dispatcher-and-claims.md). Lays the schema groundwork:
#
#   1. `claims` table — first-class record of "computer X has
#      registered intent to do piece-of-work Y on commit Z".
#      Scoped to either a full build or a single test case (TCC).
#   2. Flag/satisfaction columns on `commits` — parsed at ingest
#      from the commit message body, so the future dispatcher can
#      boost `[ci optional]` / `[ci fpe]` / `[ci converge]` commits
#      and exclude `[ci skip]` ones in a single index lookup.
#   3. Flag/claim columns on `submissions` — needed so that a
#      submission can both fulfill a claim and report which flags
#      the run was executed with (to mark the parent commit's
#      preference as satisfied).
#
# Backfills the four flag booleans on existing commits via
# Postgres POSIX regex against the FIRST LINE of the commit
# message (split_part on \n). MESA convention is that directives
# live in the subject line of the commit they apply to; squash and
# merge commits otherwise inherit every directive from every
# constituent commit and the columns become noise. The patterns
# match the `CommitMessageFlags.parse` regexes exactly so the
# columns agree with what the parser would emit — including the
# `[ci skip]` suppression when the line also mentions
# `[ci optional]` or `[ci fpe]` (ignored on `[ci converge]` to
# preserve the legacy behavior in app/models/commit.rb).
class CreateClaimsAndCiFlagColumns < ActiveRecord::Migration[8.0]
  def up
    create_table :claims do |t|
      t.references :computer, null: false, foreign_key: true
      t.references :commit,   null: false, foreign_key: true
      # set when scope='test', null when scope='build'
      t.references :test_case_commit, foreign_key: true

      t.string  :scope,  null: false                 # 'build' | 'test'
      t.string  :status, null: false, default: 'pending'
                                                     # 'pending' | 'fulfilled' | 'expired'

      t.boolean :use_fpe,           default: false, null: false
      t.boolean :use_full_inlists,  default: false, null: false
      t.boolean :use_converge,      default: false, null: false

      t.datetime :dispatched_at     # null if claim wasn't dispatcher-originated
      t.datetime :expires_at, null: false
      t.datetime :fulfilled_at      # null until submission arrives

      t.timestamps
    end

    add_index :claims, [:commit_id, :status]
    add_index :claims, [:computer_id, :status]
    add_index :claims, [:test_case_commit_id, :status]
    add_index :claims, :expires_at,
              where: "status = 'pending'",
              name: "index_claims_on_expires_at_pending"

    # scope='build' carries no TCC; scope='test' must.
    # commit_id is always set (even on test-scope claims) so
    # "all claims on this SHA" is a single index lookup, not a
    # join through test_case_commits. The model-level validation
    # backs this up by asserting tcc.commit_id == claim.commit_id.
    execute <<~SQL
      ALTER TABLE claims
      ADD CONSTRAINT claims_scope_fk_coherence CHECK (
        (scope = 'build' AND test_case_commit_id IS NULL) OR
        (scope = 'test'  AND test_case_commit_id IS NOT NULL)
      )
    SQL

    add_column :commits, :ci_skip,                 :boolean, default: false, null: false
    add_column :commits, :wants_full_inlists,      :boolean, default: false, null: false
    add_column :commits, :wants_fpe,               :boolean, default: false, null: false
    add_column :commits, :wants_converge,          :boolean, default: false, null: false
    add_column :commits, :full_inlists_satisfied_at, :datetime
    add_column :commits, :fpe_satisfied_at,          :datetime
    add_column :commits, :converge_satisfied_at,     :datetime

    add_reference :submissions, :claim, foreign_key: true
    add_column :submissions, :started_at,        :datetime
    add_column :submissions, :use_fpe,           :boolean, default: false, null: false
    add_column :submissions, :use_full_inlists,  :boolean, default: false, null: false
    add_column :submissions, :use_converge,      :boolean, default: false, null: false

    # Backfill — populate the new wants_* / ci_skip columns on every
    # existing commit by matching the same regex shapes the parser
    # uses, scoped to the first line of the message
    # (`split_part(message, E'\n', 1)`). Done in two statements so
    # wants_full_inlists / wants_fpe are set before ci_skip reads
    # them for the suppression rule.
    say_with_time "Backfilling commit flag columns from first line" do
      execute <<~SQL
        UPDATE commits SET
          wants_full_inlists = (split_part(message, E'\\n', 1) ~ '\\[[[:space:]]*ci[[:space:]]+optional([[:space:]]+[0-9]+)?[[:space:]]*\\]'),
          wants_fpe          = (split_part(message, E'\\n', 1) ~ '\\[[[:space:]]*ci[[:space:]]+fpe[[:space:]]*\\]'),
          wants_converge     = (split_part(message, E'\\n', 1) ~ '\\[[[:space:]]*ci[[:space:]]+converge[[:space:]]*\\]')
      SQL

      execute <<~SQL
        UPDATE commits SET
          ci_skip = (split_part(message, E'\\n', 1) ~ '\\[[[:space:]]*ci[[:space:]]+skip[[:space:]]*\\]')
                    AND NOT (wants_full_inlists OR wants_fpe)
      SQL
    end
  end

  def down
    remove_column :submissions, :use_converge
    remove_column :submissions, :use_full_inlists
    remove_column :submissions, :use_fpe
    remove_column :submissions, :started_at
    remove_reference :submissions, :claim, foreign_key: true

    remove_column :commits, :converge_satisfied_at
    remove_column :commits, :fpe_satisfied_at
    remove_column :commits, :full_inlists_satisfied_at
    remove_column :commits, :wants_converge
    remove_column :commits, :wants_fpe
    remove_column :commits, :wants_full_inlists
    remove_column :commits, :ci_skip

    drop_table :claims
  end
end
