module BranchMismatchRedirect
  extend ActiveSupport::Concern

  private

  # True when the resolved branch needs to be replaced with a
  # containing one — either it doesn't exist as a Branch record, or
  # it exists but doesn't include this commit. A commit a force-push
  # took off the branch isn't a mismatch: it renders there with a
  # banner saying so (sets @rewritten_away).
  def branch_mismatch?(selected_branch, commit)
    return true if selected_branch.nil?
    return false if commit.branches.include?(selected_branch)

    @rewritten_away = CommitRewrite.includes(:new_commit)
                                   .find_by(branch: selected_branch, old_commit: commit)
    @rewritten_away.nil?
  end

  # Where to send a mismatched URL: the commit's preferred branch, or,
  # for a commit force-pushes took off every branch, the branch it
  # left most recently. nil means 404.
  def branch_mismatch_target(commit)
    commit.preferred_branch ||
      CommitRewrite.where(old_commit: commit).order(rewritten_at: :desc).first&.branch
  end

  # The commits this one replaced in rebases, nearest first, for the
  # "rebased from" banner.
  def load_rebased_from(commit)
    @rebased_from = CommitRewrite.predecessors_of(commit)
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
