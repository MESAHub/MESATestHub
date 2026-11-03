# Wording for the force-push banners on the commit and test-on-commit
# pages (shared/_rewrite_banners). See CommitRewrite.
module CommitRewritesHelper
  # The predecessor worth pointing at: the nearest one with results, so
  # a commit rebased twice in quick succession (the middle version never
  # tested) still reaches the run that was. Falls back to the nearest.
  def rebase_predecessor(rewrites, test_case: nil)
    rewrites.find { |r| rewrite_results_phrase(r.old_commit, test_case: test_case) } ||
      rewrites.first
  end

  # "104 passing, 2 failing" for a commit, or "passing on 3 computers"
  # for one test on it; nil when there's nothing to report.
  def rewrite_results_phrase(commit, test_case: nil)
    if test_case
      tcc = commit.test_case_commits.find_by(test_case: test_case)
      return nil if tcc.nil? || tcc.status == -1

      word = TestCase::HEADLINE_STATUSES.fetch(tcc.status, TestCase::HEADLINE_STATUSES[-1]).first
      "#{word} on #{pluralize(tcc.computer_count, 'computer')}"
    else
      counts = { 'passing' => commit.passed_count, 'failing' => commit.failed_count,
                 'mixed' => commit.mixed_count }
      parts = counts.select { |_, n| n.to_i.positive? }.map { |word, n| "#{n} #{word}" }
      parts.join(', ').presence
    end
  end

  # The same page (commit, or test on commit) for another SHA.
  def rewrite_link_path(commit, branch, test_case: nil)
    if test_case
      test_case_commit_path(sha: commit.short_sha, branch: branch.name,
                            module: test_case.module, test_case: test_case.name)
    else
      commit_path(sha: commit.short_sha, branch: branch.name)
    end
  end

  def rewrite_date(rewrite)
    rewrite.rewritten_at.strftime('%b %-d, %Y')
  end
end
