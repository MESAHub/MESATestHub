class BranchBackfillJob < ApplicationJob
  queue_as :default

  PER_PAGE = 100

  # One-shot topology catch-up for a single branch. Walks the branch on
  # GitHub one page at a time, writing parent->child edges into
  # commit_relations for every commit pair where both ends are already in
  # the local DB.
  #
  # The walk short-circuits once a page produces zero new edges: that
  # means every commit on the page already has its parent edges recorded,
  # so every older page would too. Without this, backfilling a side
  # branch that shares almost all of its history with `main` would cost
  # ~100 API calls; with it, it's typically 1–5.
  #
  # Idempotent — the unique index on (child_id, parent_id) plus
  # insert_all's `unique_by:` makes reruns a no-op for edges already
  # present, even if the short-circuit happens to miss them on one pass.
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

      inserted = ingest_page(page)

      # Walked into history we've already edged. Every subsequent page
      # would cost an API call to learn the same thing.
      break if inserted.zero?

      # GitHub returns a short final page when we've hit the root.
      break if page.length < PER_PAGE

      page_num += 1
    end
  end

  private

  def ingest_page(commits_data)
    sha_to_id = Commit.where(sha: collect_shas(commits_data))
                      .pluck(:sha, :id)
                      .to_h

    edges = build_edges(commits_data, sha_to_id)
    return 0 if edges.empty?

    # insert_all's PostgreSQL RETURNING clause excludes ON CONFLICT
    # skips, so .length is the count of edges that were actually new.
    CommitRelation.insert_all(edges,
                              unique_by: %i[child_id parent_id]).length
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
