class BranchBackfillJob < ApplicationJob
  queue_as :default

  # One-shot topology catch-up for a single branch. Walks the branch on
  # GitHub via paginated `api.commits(sha: branch.name)` and writes
  # parent->child edges into commit_relations for every commit pair where
  # both ends are already in the local DB.
  #
  # The GitHub API includes every commit's parent SHAs in the same
  # response that the old sync code was already making — we just weren't
  # recording them. So this job's API budget is the same paginated walk
  # the old code did, no new request types.
  #
  # Idempotent: the unique index on (child_id, parent_id) plus insert_all's
  # `unique_by:` makes reruns a no-op for edges already present.
  def perform(branch_id)
    branch = Branch.find(branch_id)

    commits_data = Commit.api_commits(sha: branch.name)
    return if commits_data.blank?

    sha_to_id = Commit.where(sha: collect_shas(commits_data))
                      .pluck(:sha, :id)
                      .to_h

    edges = build_edges(commits_data, sha_to_id)
    return if edges.empty?

    CommitRelation.insert_all(edges, unique_by: %i[child_id parent_id])
  end

  private

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
