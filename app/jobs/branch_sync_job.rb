class BranchSyncJob < ApplicationJob
  queue_as :default

  # Webhook-driven sync for a single push event. The controller passes
  # in the relevant fields of the GitHub push webhook payload; this job
  # dispatches to one of three handlers based on what kind of event it
  # is (deletion, creation, or normal push).
  #
  # Normal pushes call api.compare(before, after) once to get the
  # canonical ordered commit list with parent metadata (the push
  # webhook payload's commits[] array doesn't include parent SHAs),
  # then bulk-upsert via the helpers on Commit and Branch.
  def perform(payload)
    payload = payload.deep_symbolize_keys
    ref = payload[:ref]
    return unless ref&.start_with?('refs/heads/')

    branch_name = ref.delete_prefix('refs/heads/')

    case
    when payload[:deleted]
      handle_deletion(branch_name)
    when payload[:created]
      handle_creation(branch_name, payload)
    else
      handle_push(branch_name, payload)
    end
  end

  private

  def handle_deletion(branch_name)
    branch = Branch.find_by(name: branch_name)
    return unless branch

    Branch.transaction do
      branch.branch_memberships.delete_all
      branch.delete
    end
  end

  # Brand new branch. The webhook tells us the head SHA but not always
  # the full ancestry, so we lean on BranchBackfillJob to walk
  # api.commits(sha: branch_name) and populate both edges and
  # memberships. Then set the head pointer from the now-present commit.
  def handle_creation(branch_name, payload)
    branch = Branch.find_or_create_by!(name: branch_name)

    BranchBackfillJob.perform_now(branch.id)

    head_commit = Commit.find_by(sha: payload[:after])
    branch.update!(head_id: head_commit.id) if head_commit
  end

  def handle_push(branch_name, payload)
    branch = Branch.find_by(name: branch_name)

    # A push to a branch we don't know about means we missed the
    # creation event. Treat it as creation so the full ancestry gets
    # populated, then return.
    if branch.nil?
      Rails.logger.warn(
        "BranchSyncJob: push to unknown branch '#{branch_name}', " \
        "handling as creation"
      )
      handle_creation(branch_name, payload)
      return
    end

    before = payload[:before]
    after  = payload[:after]

    comparison = Commit.api.compare(Commit.repo_path, before, after)
    commits    = Array(comparison && comparison[:commits])
    # A force-push either diverges from the old head (rebase, amend) or
    # moves the head back to an ancestor (reset), which compares with no
    # commits at all but still drops some.
    rewritten = payload[:forced] || %w[diverged behind].include?(comparison && comparison[:status].to_s)
    return if commits.empty? && !rewritten

    sha_to_id = Commit.ingest_payload_commits(commits)
    Commit.ingest_payload_edges(commits, sha_to_id)

    # populate_payload_test_cases runs AFTER edges so the
    # copy-from-parent optimization can find each new commit's parent
    # via commit_relations. The webhook payload's commits[] array
    # carries per-commit file change lists (added/modified) that let
    # the populator know when sources actually changed — for those
    # commits we re-fetch via api.content; for the rest we copy from
    # parent (zero API calls). Webhook commits[] truncates at 20, so
    # commits past that cap fall back to the copy-from-parent default.
    file_changes_by_sha = build_file_changes_map(payload[:commits])
    Commit.populate_payload_test_cases(commits, sha_to_id,
                                       file_changes_by_sha: file_changes_by_sha)

    # compare lists at most 250 commits, oldest first, so a long push
    # (a rebase onto a lot of new main history, say) arrives without its
    # newest commits, head included. Walk the branch from its tip on
    # GitHub instead; the backfill stops once it reaches known history.
    if comparison && comparison[:total_commits].to_i > commits.size
      BranchBackfillJob.perform_now(branch.id)
    end

    if (head_id = sha_to_id[after] || Commit.where(sha: after).pick(:id))
      branch.update!(head_id: head_id)
    end

    branch.absorb_commits(sha_to_id.values)

    absorb_merge_ancestors(branch, commits)

    record_rewrite(branch, before, after) if rewritten
  end

  # A real rewrite drops a branch's own stack: tens of commits. Many more
  # means the new head's walk broke on a missing edge and the "dropped"
  # walk ran into shared history, so the memberships are left alone.
  MAX_REWRITE_DROP = 500

  # Take what the force-push dropped off the branch, pairing each
  # dropped commit with its rebased replacement where one matches.
  def record_rewrite(branch, before, after)
    branch.reload
    dropped = branch.commits_dropped_since(before)
    return if dropped.empty?

    if dropped.size > MAX_REWRITE_DROP
      Rails.logger.warn(
        "BranchSyncJob: force-push to '#{branch.name}' would drop #{dropped.size} " \
        "commits; skipping (check commit_relations for a missing edge)"
      )
      return
    end

    branch.record_rewrite(dropped_ids: dropped,
                          candidate_ids: branch.commits_added_since(before),
                          before_sha: before, after_sha: after)
  end

  # Convert the webhook payload's commits[] array into a
  # `sha => Array<file_path>` map. Combines added + modified (we don't
  # care about removed for the test-case check). Returns nil when the
  # webhook didn't supply commits[] (which shouldn't happen for normal
  # pushes but does for synthetic events from reconcile).
  def build_file_changes_map(webhook_commits)
    return nil if webhook_commits.blank?

    webhook_commits.each_with_object({}) do |c, map|
      c = c.deep_symbolize_keys if c.respond_to?(:deep_symbolize_keys)
      sha = c[:id] || c[:sha]
      next unless sha

      map[sha] = Array(c[:added]) + Array(c[:modified])
    end
  end

  # For each merge commit in the push, walk back via the foreign
  # parent(s) and add memberships for every commit thereby brought
  # onto this branch. GitHub orders a merge commit's parents with the
  # receiving branch's previous head first, foreign branches second
  # and beyond.
  def absorb_merge_ancestors(branch, commits)
    commits.each do |c|
      next unless c[:parents].size > 1

      foreign_parent_shas = c[:parents].drop(1).map { |p| p[:sha] }
      foreign_parent_ids  = Commit.where(sha: foreign_parent_shas)
                                  .pluck(:id)
      branch.absorb_merge(foreign_parent_ids)
    end
  end
end
