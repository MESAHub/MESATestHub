require 'rails_helper'

# Specs for the Phase 3.5 webhook-payload ingestion helpers on Commit.
# These are called from BranchSyncJob with the output of
# api.compare(before, after) (or api.commits when we want to ingest
# arbitrary windows from outside the push flow).
RSpec.describe Commit, 'payload ingestion' do
  # Shape commit hashes the way Octokit returns them from
  # api.commits / api.compare. Plain symbol-keyed hashes are fine —
  # Sawyer::Resource supports `[:foo]` lookup identically.
  def gh_commit(sha:, parent_shas: [], author: 'Test Author',
                email: 'author@example.com', message: 'msg',
                date: Time.zone.parse('2026-01-01T12:00:00Z'),
                committer_date: nil)
    {
      sha: sha,
      commit: {
        author:    { name: author, email: email, date: date },
        committer: { name: author, email: email,
                     date: committer_date || date },
        message: message
      },
      html_url: "https://github.com/MESAHub/mesa/commit/#{sha}",
      parents: parent_shas.map { |s| { sha: s } }
    }
  end

  def sha40(prefix)
    prefix.to_s.ljust(40, '0')
  end

  describe '.ingest_payload_commits' do
    it 'inserts new commits and returns a sha => id map' do
      payload = [
        gh_commit(sha: sha40('aaaa1')),
        gh_commit(sha: sha40('bbbb2'))
      ]

      result = nil
      expect { result = Commit.ingest_payload_commits(payload) }
        .to change(Commit, :count).by(2)

      expect(result.keys).to contain_exactly(sha40('aaaa1'), sha40('bbbb2'))
      expect(Commit.find(result[sha40('aaaa1')]).author).to eq('Test Author')
    end

    it 'is a no-op for an empty payload' do
      expect { Commit.ingest_payload_commits([]) }
        .not_to change(Commit, :count)
    end

    it 'is idempotent: re-ingesting an existing commit preserves its row' do
      # Real GitHub commits are immutable, so insert-then-skip is the
      # correct semantics. Crucially this means we never clobber the
      # test_case_count / passed_count / status scalars maintained by
      # update_scalars for commits ingested before Phase 3.5. We use
      # update_columns here to skip the before_save callback that
      # would otherwise overwrite the test scalars based on the
      # (empty) test_case_commits association.
      original = create(:commit, sha: sha40('cccc3'),
                                 short_sha: sha40('cccc3')[0, 7],
                                 author: 'Original Author')
      original.update_columns(status: 0, test_case_count: 5, passed_count: 5)

      payload = [gh_commit(sha: sha40('cccc3'), author: 'Different')]

      expect { Commit.ingest_payload_commits(payload) }
        .not_to change(Commit, :count)

      original.reload
      expect(original.author).to eq('Original Author')
      expect(original.status).to eq(0)
      expect(original.test_case_count).to eq(5)
      expect(original.passed_count).to eq(5)
    end

    it 'sets status to -1 ("untested") on newly inserted commits' do
      # The schema default is 0, which the view treats as "passing"
      # (btn-success). Bypassing the update_scalars callback means
      # we'd get 0 by default; explicit -1 makes new commits look
      # untested until test data arrives.
      Commit.ingest_payload_commits([gh_commit(sha: sha40('newone'))])

      expect(Commit.find_by(sha: sha40('newone')).status).to eq(-1)
    end

    it 'does not fire api_update_test_cases on freshly inserted commits' do
      # insert_all bypasses validations and callbacks. That's the whole
      # point — we don't want every webhook ingestion to fan out into
      # api.content() calls per commit per module.
      expect_any_instance_of(Commit).not_to receive(:api_update_test_cases)
      Commit.ingest_payload_commits([gh_commit(sha: sha40('dddd4'))])
    end

    it 'stores commit_time from the committer date, not the author date' do
      # Rebase-and-merge / Squash-and-merge / amend rewrite a commit
      # with a new committer date but preserve the original author
      # date. GitHub orders /commits/<branch> by committer date and
      # treats the head as the most-recently-committed commit; all
      # our views sort by commit_time, so commit_time must read the
      # committer date or the head won't sit at the top of every list.
      author_date    = Time.zone.parse('2026-03-15T10:00:00Z')
      committer_date = Time.zone.parse('2026-03-20T08:00:00Z')
      payload = [gh_commit(sha: sha40('rebase1'),
                           date: author_date,
                           committer_date: committer_date)]

      Commit.ingest_payload_commits(payload)

      row = Commit.find_by(sha: sha40('rebase1'))
      expect(row.commit_time).to be_within(1.second).of(committer_date)
      expect(row.commit_time).not_to be_within(1.second).of(author_date)
    end
  end

  describe '.ingest_payload_edges' do
    it 'inserts a parent->child edge when both ends are in the payload' do
      payload = [
        gh_commit(sha: sha40('parent1')),
        gh_commit(sha: sha40('child1'), parent_shas: [sha40('parent1')])
      ]
      sha_to_id = Commit.ingest_payload_commits(payload)

      expect { Commit.ingest_payload_edges(payload, sha_to_id) }
        .to change(CommitRelation, :count).by(1)

      edge = CommitRelation.last
      expect(edge.parent_id).to eq(sha_to_id[sha40('parent1')])
      expect(edge.child_id).to eq(sha_to_id[sha40('child1')])
      expect(edge.parent_index).to eq(0)
    end

    it 'looks up parents not in the payload (older than the compare window)' do
      pre_existing = create(:commit, sha: sha40('old'),
                                     short_sha: sha40('old')[0, 7])
      payload = [
        gh_commit(sha: sha40('new'), parent_shas: [pre_existing.sha])
      ]
      sha_to_id = Commit.ingest_payload_commits(payload)
      # Note: sha_to_id only contains the new commit, not the
      # pre_existing one — that's the case we're exercising.
      expect(sha_to_id.keys).to eq([sha40('new')])

      expect { Commit.ingest_payload_edges(payload, sha_to_id) }
        .to change(CommitRelation, :count).by(1)

      edge = CommitRelation.last
      expect(edge.parent_id).to eq(pre_existing.id)
    end

    it 'skips orphan parents (parent SHA not in DB)' do
      payload = [
        gh_commit(sha: sha40('orphan_child'),
                  parent_shas: [sha40('never_seen')])
      ]
      sha_to_id = Commit.ingest_payload_commits(payload)

      expect { Commit.ingest_payload_edges(payload, sha_to_id) }
        .not_to change(CommitRelation, :count)
    end

    it 'records every parent of a merge commit with its parent_index' do
      payload = [
        gh_commit(sha: sha40('p1')),
        gh_commit(sha: sha40('p2')),
        gh_commit(sha: sha40('merge'),
                  parent_shas: [sha40('p1'), sha40('p2')])
      ]
      sha_to_id = Commit.ingest_payload_commits(payload)

      Commit.ingest_payload_edges(payload, sha_to_id)

      edges = CommitRelation.where(child_id: sha_to_id[sha40('merge')])
                            .order(:parent_index)
      expect(edges.map { |e| [e.parent_id, e.parent_index] }).to eq([
        [sha_to_id[sha40('p1')], 0],
        [sha_to_id[sha40('p2')], 1]
      ])
    end

    it 'is idempotent: rerunning with the same payload does not duplicate edges' do
      payload = [
        gh_commit(sha: sha40('p')),
        gh_commit(sha: sha40('c'), parent_shas: [sha40('p')])
      ]
      sha_to_id = Commit.ingest_payload_commits(payload)
      Commit.ingest_payload_edges(payload, sha_to_id)

      expect { Commit.ingest_payload_edges(payload, sha_to_id) }
        .not_to change(CommitRelation, :count)
    end

    it 'returns the count of newly-inserted edges' do
      payload = [
        gh_commit(sha: sha40('p')),
        gh_commit(sha: sha40('c'), parent_shas: [sha40('p')])
      ]
      sha_to_id = Commit.ingest_payload_commits(payload)

      expect(Commit.ingest_payload_edges(payload, sha_to_id)).to eq(1)
      # Second time, all edges already present
      expect(Commit.ingest_payload_edges(payload, sha_to_id)).to eq(0)
    end

    it 'is a no-op for an empty payload' do
      expect { Commit.ingest_payload_edges([], {}) }
        .not_to change(CommitRelation, :count)
    end
  end

  # The CI directive flag columns added in Phase A of the
  # dispatcher+claims feature get populated from the commit
  # message at ingest. Both ingest paths run through
  # `hash_from_github`, which merges in `CommitMessageFlags.parse`,
  # so verifying the bulk path covers the regular AR path too.
  describe 'CI directive flag columns at ingest' do
    it 'populates wants_full_inlists for a [ci optional] commit' do
      Commit.ingest_payload_commits(
        [gh_commit(sha: sha40('opt'), message: "Refactor [ci optional]")]
      )
      row = Commit.find_by(sha: sha40('opt'))
      expect(row.wants_full_inlists).to be true
      expect(row.wants_fpe).to be false
      expect(row.ci_skip).to be false
    end

    it 'populates wants_fpe and wants_converge together' do
      Commit.ingest_payload_commits(
        [gh_commit(sha: sha40('flag'),
                   message: "Tune solver [ci fpe] [ci converge]")]
      )
      row = Commit.find_by(sha: sha40('flag'))
      expect(row.wants_fpe).to be true
      expect(row.wants_converge).to be true
      expect(row.ci_skip).to be false
    end

    it 'populates ci_skip for a plain [ci skip] commit' do
      Commit.ingest_payload_commits(
        [gh_commit(sha: sha40('skip'), message: "Bump version [ci skip]")]
      )
      row = Commit.find_by(sha: sha40('skip'))
      expect(row.ci_skip).to be true
      expect(row.wants_full_inlists).to be false
    end

    it 'suppresses ci_skip when [ci optional] is also present' do
      Commit.ingest_payload_commits(
        [gh_commit(sha: sha40('mrge'),
                   message: "Merge cleanup [ci skip] [ci optional]")]
      )
      row = Commit.find_by(sha: sha40('mrge'))
      expect(row.ci_skip).to be false
      expect(row.wants_full_inlists).to be true
    end

    it 'leaves all flags false for a vanilla commit' do
      Commit.ingest_payload_commits(
        [gh_commit(sha: sha40('clean'), message: "Add missing comma")]
      )
      row = Commit.find_by(sha: sha40('clean'))
      expect(row.ci_skip).to be false
      expect(row.wants_full_inlists).to be false
      expect(row.wants_fpe).to be false
      expect(row.wants_converge).to be false
    end

    it 'populates flags via the AR create_or_update path too' do
      payload = gh_commit(sha: sha40('aronly'),
                          message: "Big change [ci fpe]")
      commit = Commit.create_or_update_from_github_hash(github_hash: payload)
      expect(commit.wants_fpe).to be true
      expect(commit.ci_skip).to be false
    end

    it 'ignores directives that appear only in the message body' do
      # Squash/merge commits typically include each squashed
      # commit's subject in the body. Scanning the whole message
      # would inherit every directive from every constituent
      # commit; only the merge commit's own subject line counts.
      Commit.ingest_payload_commits(
        [gh_commit(sha: sha40('mbody'),
                   message: "Merge feature-X (#42)\n\n" \
                            "* Tidy [ci skip]\n" \
                            "* Solver swap [ci fpe]\n" \
                            "* All-inlists pass [ci optional]\n")]
      )
      row = Commit.find_by(sha: sha40('mbody'))
      expect(row.ci_skip).to be false
      expect(row.wants_fpe).to be false
      expect(row.wants_full_inlists).to be false
    end
  end
end
