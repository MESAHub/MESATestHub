module BranchMismatchRedirect
  extend ActiveSupport::Concern

  private

  # True when the resolved branch needs to be replaced with a
  # containing one — either it doesn't exist as a Branch record, or
  # it exists but doesn't include this commit.
  def branch_mismatch?(selected_branch, commit)
    selected_branch.nil? || !commit.branches.include?(selected_branch)
  end

  # Human-readable flash for the branch-mismatch redirect. Plain text
  # (no inline HTML); the layout escapes flash values.
  def branch_mismatch_message(requested_name:, requested_branch:, target:, commit:)
    others = commit.branches.reject { |b| b == target }.map(&:name).sort
    suffix = others.any? ? " Also on: #{others.join(', ')}." : ""

    reason =
      if requested_branch.nil?
        "Branch '#{requested_name}' doesn't exist."
      else
        "Branch '#{requested_name}' doesn't contain commit #{commit.short_sha}."
      end

    "#{reason} Showing it on '#{target.name}' instead.#{suffix}"
  end
end
