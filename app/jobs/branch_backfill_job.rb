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
    sha_to_id = Commit.where(sha: collect_shas(commits_data))
                      .pluck(:sha, :id)
                      .to_h

    [insert_edges(commits_data, sha_to_id),
     insert_memberships(branch, commits_data, sha_to_id)]
  end

  def insert_edges(commits_data, sha_to_id)
    edges = build_edges(commits_data, sha_to_id)
    return 0 if edges.empty?

    # insert_all's PostgreSQL RETURNING clause excludes ON CONFLICT
    # skips, so .length is the count of edges that were actually new.
    CommitRelation.insert_all(edges,
                              unique_by: %i[child_id parent_id]).length
  end

  def insert_memberships(branch, commits_data, sha_to_id)
    commit_ids = commits_data.map { |c| sha_to_id[c[:sha]] }.compact
    return 0 if commit_ids.empty?

    rows = commit_ids.map { |id| { branch_id: branch.id, commit_id: id } }
    BranchMembership.insert_all(rows,
                                unique_by: %i[commit_id branch_id]).length
  end

  def collect_shas(commits_data)
    shas = Set.new
    commits_data.each do |commit_hash|
      shas << commit_hash[:sha]
      commit_hash[:parents].each { |parent| shas << parent[:sha] }
    end
    shas.to_a
  end

  def build_edges(commits_data, sha_to_id)
    edges = []
    commits_data.each do |commit_hash|
      child_id = sha_to_id[commit_hash[:sha]]
      next unless child_id

      commit_hash[:parents].each_with_index do |parent, idx|
        parent_id = sha_to_id[parent[:sha]]
        next unless parent_id

        edges << { parent_id: parent_id,
                   child_id: child_id,
                   parent_index: idx }
      end
    end
    edges
  end
end
