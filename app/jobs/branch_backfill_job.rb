class BranchBackfillJob < ApplicationJob
  queue_as :default

  PER_PAGE = 100

  # One-shot topology catch-up for a single branch. Walks the branch on
  # GitHub one page at a time, writing parent->child edges into
  # commit_relations and (branch, commit) rows into branch_memberships
  # for every commit pair / commit where both ends / the commit is in
  # the local DB.
  #
  # The walk short-circuits once a page produces zero new edges AND
  # zero new memberships: that means every commit on the page is fully
  # caught up, so every older page would be too. Without the
  # memberships check the short-circuit would fire too early on
  # newly-created branches whose ancestors are already edged from
  # main's backfill but have no membership rows yet for the new branch.
  #
  # Backfilling a side branch that shares almost all of its history
  # with `main` typically costs 1–5 API calls thanks to the
  # short-circuit. Idempotent — the unique indexes on
  # (child_id, parent_id) and (commit_id, branch_id) plus insert_all's
  # `unique_by:` make reruns no-ops for rows already present.
  def perform(branch_id)
    branch = Branch.find(branch_id)
    client = Commit.api(auto_paginate: false)

    page_num = 1
    loop do
      page = client.commits(Commit.repo_path,
                            sha: branch.name,
                            per_page: PER_PAGE,
                            page: page_num)
      break if page.blank?

      new_edges, new_memberships = ingest_page(page, branch)

      # Walked into territory where every commit is already edged and
      # already a member. Every subsequent page would cost an API call
      # to learn the same thing.
      break if new_edges.zero? && new_memberships.zero?

      # GitHub returns a short final page when we've hit the root.
      break if page.length < PER_PAGE

      page_num += 1
    end
  end

  private

  def ingest_page(commits_data, branch)
    # Insert the commits first so we have rows for every SHA in the
    # page — including ones we've never seen, which is the common case
    # when this job is invoked from BranchSyncJob#handle_creation for a
    # brand-new branch with new commits. ingest_payload_commits returns
    # the sha => id map we need for edges and memberships.
    #
    # For the topology:backfill rake task, commits typically already
    # exist (the old sync code created them). Inserting them again is
    # a quick idempotent op (insert_all skips on conflict).
    sha_to_id = Commit.ingest_payload_commits(commits_data)

    edges_inserted = Commit.ingest_payload_edges(commits_data, sha_to_id)
    memberships_inserted = insert_memberships(branch, sha_to_id.values)

    # Populate test cases for any freshly-inserted commits. Backfill
    # has no per-commit file-change info, so the populator defaults
    # to copy-from-parent (which finds parents via the edges we just
    # inserted) and falls back to api.content for orphans.
    Commit.populate_payload_test_cases(commits_data, sha_to_id)

    [edges_inserted, memberships_inserted]
  end

  def insert_memberships(branch, commit_ids)
    return 0 if commit_ids.empty?

    rows = commit_ids.map { |id| { branch_id: branch.id, commit_id: id } }
    BranchMembership.insert_all(rows,
                                unique_by: %i[commit_id branch_id]).length
  end
end
