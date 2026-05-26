module TestInstancesHelper
  # Pick the branch slug to use in a commit / test-case URL for a
  # given commit. Prefers `main` when the commit lives there,
  # otherwise picks the first containing branch alphabetically.
  # Falls back to `"main"` for the edge case of a commit with no
  # branch memberships (the controller's branch-fallback will catch
  # the mismatch and redirect to a real branch).
  #
  # Expects `commit.branches` to already be eager-loaded — the
  # search query does this via TestInstance.query's includes.
  def best_branch_name_for(commit)
    branches = commit.branches.to_a
    return "main" if branches.empty?
    return "main" if branches.any? { |b| b.name == "main" }
    branches.min_by(&:name).name
  end
end
