# Rails.cache for CommitState#commit_state, the summary hash behind every
# status ring, pill, and chip on the list pages (commits index, home page
# sections and unified view, recent-branch cards, the hero subway map,
# the diff tab's clean-baseline walk).
#
# Computing one costs every TCC and test instance on the commit: a busy
# commit has hundreds of instances, and an index page of 25 commits
# loaded ~6,700 of them per request. The result is a small hash that
# changes only when the commit's data does, so it caches well.
#
# Invalidation is by fingerprint, not by expiry or callbacks: the key
# carries, per commit, the row count and newest updated_at of each table
# commit_state reads (submissions, test_instances, test_case_commits,
# claims). Any insert, delete, or timestamped update changes the key.
# Callbacks wouldn't do: claims change through insert_all / update_all
# (claim creation, the sweeper, fulfillment), which skip them, though
# every one of those writes sets updated_at. One query fingerprints a
# whole page of commits.
#
# Nothing in commit_state reads the clock or the viewer, so a key match
# means the cached hash is what a fresh computation would return. The
# key also carries a digest of the files that define the rules
# (RULES_FILES), so a deploy that changes them never serves hashes from
# before it, while other deploys keep the cache (Solid Cache outlives the
# process). Bump VERSION for a rules change that lives elsewhere.
class CommitStateCache
  VERSION = 1

  # Where commit_state's logic lives. Add a file here if it starts
  # deciding statuses, flags, or counts.
  RULES_FILES = %w[
    app/models/concerns/commit_state.rb
    app/services/checksum_comparison.rb
    app/models/test_instance.rb
    app/models/test_case_commit.rb
    app/models/test_case.rb
    app/models/claim.rb
  ].freeze

  # What commit_state reads, preloaded in one batch for the commits that
  # missed. Matches CommitState#_tccs_for_matrix.
  PRELOAD = [:submissions, :pending_claims,
             { test_case_commits: %i[test_case test_instances pending_claims] }].freeze

  FINGERPRINT_TABLES = %w[submissions test_instances test_case_commits claims].freeze

  # { commit.id => commit_state } for every commit, computing (and
  # caching) the misses together.
  def self.fetch(commits)
    new(commits).fetch_all
  end

  def initialize(commits)
    @commits = commits.compact.uniq(&:id)
    @fingerprints = self.class.fingerprints(@commits.map(&:id))
  end

  def fetch_all
    hits = read_all
    misses = @commits.reject { |c| hits.key?(c.id) }
    return hits if misses.empty?

    ActiveRecord::Associations::Preloader.new(records: misses, associations: PRELOAD).call
    computed = misses.to_h { |c| [c.id, c.commit_state] }
    Rails.cache.write_multi(misses.to_h { |c| [key_for(c), computed[c.id]] })
    hits.merge(computed)
  end

  # Cached states only; commits that missed are absent. For callers that
  # want to stop computing early (Branch#last_clean_commit_before).
  def read_all
    keys = @commits.to_h { |c| [key_for(c), c.id] }
    Rails.cache.read_multi(*keys.keys).transform_keys { |key| keys[key] }
  end

  # One commit's state: cached, or computed and written.
  def fetch_one(commit)
    Rails.cache.fetch(key_for(commit)) { commit.commit_state }
  end

  def key_for(commit)
    ['commit_state', VERSION, self.class.rules_digest, commit.id, @fingerprints[commit.id]]
  end

  # Recomputed on code reload in development, since the class reloads
  # with the files.
  def self.rules_digest
    @rules_digest ||= Digest::SHA256.hexdigest(
      RULES_FILES.map { |path| Rails.root.join(path).read }.join("\0")
    ).first(12)
  end

  # { commit_id => "n:t|n:t|…" } with one (count, newest updated_at)
  # pair per FINGERPRINT_TABLES entry. Every table is indexed on
  # commit_id.
  def self.fingerprints(commit_ids)
    return {} if commit_ids.empty?

    parts = FINGERPRINT_TABLES.map do |table|
      "(SELECT count(*) || ':' || coalesce(floor(extract(epoch FROM max(updated_at)) * 1000000)::bigint::text, '') " \
        "FROM #{table} WHERE #{table}.commit_id = commits.id)"
    end
    sql = "SELECT commits.id, #{parts.join(" || '|' || ")} FROM commits WHERE commits.id IN (?)"
    Commit.connection.select_rows(Commit.sanitize_sql_array([sql, commit_ids]))
          .to_h { |id, print| [id.to_i, print] }
  end
end
