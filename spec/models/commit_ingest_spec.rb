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
                date: Time.zone.parse('2026-01-01T12:00:00Z'))
    {
      sha: sha,
      commit: {
        author: { name: author, email: email, date: date },
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

    it 'is idempotent: existing commits are updated, not duplicated' do
      payload = [gh_commit(sha: sha40('cccc3'), author: 'Original')]
      Commit.ingest_payload_commits(payload)

      payload[0] = gh_commit(sha: sha40('cccc3'), author: 'Revised')

      expect { Commit.ingest_payload_commits(payload) }
        .not_to change(Commit, :count)

      expect(Commit.find_by(sha: sha40('cccc3')).author).to eq('Revised')
    end

    it 'does not fire api_update_test_cases on freshly inserted commits' do
      # upsert_all bypasses validations and callbacks. That's the whole
      # point — we don't want every webhook ingestion to fan out into
      # api.content() calls per commit per module.
      expect_any_instance_of(Commit).not_to receive(:api_update_test_cases)
      Commit.ingest_payload_commits([gh_commit(sha: sha40('dddd4'))])
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
end
