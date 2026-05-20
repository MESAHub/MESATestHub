require 'rails_helper'

# Specs for the test-case population that runs as part of (and after)
# Commit.ingest_payload_commits. This is what restores correctness of
# the commit index page's test counts for new commits.
RSpec.describe Commit, 'test case population' do
  describe '.copy_test_cases_from_parent' do
    let(:test_case_1) { create(:test_case, name: 'evolve_zams', module: 'star') }
    let(:test_case_2) { create(:test_case, name: 'wd_he_diff', module: 'star') }

    let(:parent) do
      p = create(:commit)
      TestCaseCommit.create!(commit: p, test_case: test_case_1)
      TestCaseCommit.create!(commit: p, test_case: test_case_2)
      p
    end

    let(:child) { create(:commit) }

    before do
      CommitRelation.create!(parent: parent, child: child, parent_index: 0)
    end

    it 'copies all of the parent\'s TCCs to the child' do
      expect { Commit.copy_test_cases_from_parent(child) }
        .to change(TestCaseCommit, :count).by(2)

      expect(child.reload.test_cases).to match_array([test_case_1, test_case_2])
    end

    it 'resets per-commit counters on the copied TCCs' do
      # Bump the parent's TCCs to confirm we don't carry the counters over
      parent.test_case_commits.update_all(status: 0, submission_count: 5,
                                          computer_count: 3, passed_count: 5)

      Commit.copy_test_cases_from_parent(child)

      copied = child.test_case_commits
      expect(copied.pluck(:status)).to all(eq(-1))
      expect(copied.pluck(:submission_count)).to all(eq(0))
      expect(copied.pluck(:computer_count)).to all(eq(0))
      expect(copied.pluck(:passed_count)).to all(eq(0))
    end

    it 'updates the child commit\'s scalars (test_case_count, status)' do
      Commit.copy_test_cases_from_parent(child)

      child.reload
      expect(child.test_case_count).to eq(2)
      expect(child.untested_count).to eq(2)
      expect(child.status).to eq(-1)  # everything untested
    end

    it 'returns false when the commit has no parent' do
      lonely = create(:commit)
      expect(Commit.copy_test_cases_from_parent(lonely)).to be false
    end

    it 'returns false when the parent has no TCCs' do
      empty_parent = create(:commit)
      child2 = create(:commit)
      CommitRelation.create!(parent: empty_parent, child: child2, parent_index: 0)

      expect(Commit.copy_test_cases_from_parent(child2)).to be false
    end

    it 'is idempotent: re-running does not create duplicate TCCs' do
      Commit.copy_test_cases_from_parent(child)

      expect { Commit.copy_test_cases_from_parent(child) }
        .not_to change(TestCaseCommit, :count)
    end
  end

  describe '.populate_test_cases_for' do
    let(:parent) do
      p = create(:commit)
      tc = create(:test_case, name: 'tc1', module: 'star')
      TestCaseCommit.create!(commit: p, test_case: tc)
      p
    end

    let(:commit) do
      c = create(:commit)
      CommitRelation.create!(parent: parent, child: c, parent_index: 0)
      c
    end

    it 'copies from parent when sources_touched: false' do
      result = Commit.populate_test_cases_for(commit, sources_touched: false)
      expect(result).to eq(:copied)
      expect(commit.reload.test_case_count).to eq(1)
    end

    it 'copies from parent when sources_touched: nil (unknown) and parent has TCCs' do
      result = Commit.populate_test_cases_for(commit, sources_touched: nil)
      expect(result).to eq(:copied)
    end

    it 'fetches via api when sources_touched: true' do
      expect(commit).to receive(:api_update_test_cases)
      result = Commit.populate_test_cases_for(commit, sources_touched: true)
      expect(result).to eq(:fetched)
    end

    it 'fetches via api when parent has no TCCs (copy would fail)' do
      empty_parent = create(:commit)
      child2 = create(:commit)
      CommitRelation.create!(parent: empty_parent, child: child2, parent_index: 0)

      expect(child2).to receive(:api_update_test_cases)
      result = Commit.populate_test_cases_for(child2)
      expect(result).to eq(:fetched)
    end

    it 'fetches via api when commit has no parent' do
      lonely = create(:commit)
      expect(lonely).to receive(:api_update_test_cases)

      result = Commit.populate_test_cases_for(lonely)
      expect(result).to eq(:fetched)
    end
  end

  describe '.populate_payload_test_cases' do
    def gh_commit(sha:, parent_shas: [])
      {
        sha: sha,
        commit: {
          author: { name: 'Bot', email: 'bot@example.com',
                    date: Time.zone.parse('2026-01-01T12:00:00Z') },
          message: "msg #{sha[0, 7]}"
        },
        html_url: "https://github.com/MESAHub/mesa/commit/#{sha}",
        parents: parent_shas.map { |s| { sha: s } }
      }
    end

    def sha40(prefix)
      prefix.to_s.ljust(40, '0')
    end

    it 'copies from parent for a freshly-ingested commit (full pipeline)' do
      tc = create(:test_case, name: 'evolve_zams', module: 'star')
      parent = create(:commit, sha: sha40('parent'),
                               short_sha: sha40('parent')[0, 7])
      TestCaseCommit.create!(commit: parent, test_case: tc)
      parent.save  # update_scalars

      payload = [gh_commit(sha: sha40('new'), parent_shas: [parent.sha])]

      sha_to_id = Commit.ingest_payload_commits(payload)
      Commit.ingest_payload_edges(payload, sha_to_id)
      Commit.populate_payload_test_cases(payload, sha_to_id)

      new_commit = Commit.find_by(sha: sha40('new'))
      expect(new_commit.test_case_count).to eq(1)
      expect(new_commit.test_cases).to eq([tc])
    end

    it 'fetches via api when webhook says sources were touched' do
      tc = create(:test_case, name: 'evolve_zams', module: 'star')
      parent = create(:commit, sha: sha40('parent'),
                               short_sha: sha40('parent')[0, 7])
      TestCaseCommit.create!(commit: parent, test_case: tc)

      payload = [gh_commit(sha: sha40('new'), parent_shas: [parent.sha])]
      file_changes = { sha40('new') => ['star/test_suite/do1_test_source'] }

      sha_to_id = Commit.ingest_payload_commits(payload)
      Commit.ingest_payload_edges(payload, sha_to_id)

      expect_any_instance_of(Commit).to receive(:api_update_test_cases)
      Commit.populate_payload_test_cases(payload, sha_to_id,
                                         file_changes_by_sha: file_changes)
    end

    it 'fetches via api when no parent is in the DB' do
      payload = [gh_commit(sha: sha40('lone'))]
      sha_to_id = Commit.ingest_payload_commits(payload)
      Commit.ingest_payload_edges(payload, sha_to_id)

      expect_any_instance_of(Commit).to receive(:api_update_test_cases)
      Commit.populate_payload_test_cases(payload, sha_to_id)
    end

    it 'skips commits that already have TCCs (test_case_count > 0)' do
      tc = create(:test_case)
      already_done = create(:commit, sha: sha40('done'),
                                     short_sha: sha40('done')[0, 7])
      TestCaseCommit.create!(commit: already_done, test_case: tc)
      already_done.save  # update_scalars → test_case_count = 1

      payload = [gh_commit(sha: already_done.sha)]
      sha_to_id = { already_done.sha => already_done.id }

      expect_any_instance_of(Commit).not_to receive(:api_update_test_cases)
      Commit.populate_payload_test_cases(payload, sha_to_id)
    end

    it 'processes a chain of new commits in commit_time ASC so each ' \
       'child can copy from its just-populated parent (single api fetch)' do
      # Regression: previously this iterated via find_each (id ASC),
      # which under backfill processes newest-first. Each commit's
      # parent hadn't been populated yet, so every commit cascaded
      # into api_update_test_cases — 3 API calls per commit instead
      # of 1 for the whole chain.
      tc = create(:test_case, name: 'evolve_zams', module: 'star')
      seed = create(:commit, sha: sha40('seed'),
                             short_sha: sha40('seed')[0, 7])
      TestCaseCommit.create!(commit: seed, test_case: tc)
      seed.save  # update_scalars → test_case_count = 1

      # Build a chain: seed (has TCC) ← oldest ← middle ← newest
      # All three children have higher IDs (more recently inserted)
      # than their parents, but earlier commit_time means they should
      # process first.
      base_time = Time.zone.parse('2026-01-01T00:00:00Z')
      oldest_sha = sha40('oldest')
      middle_sha = sha40('middle')
      newest_sha = sha40('newest')

      # Insert in newest-first order to mimic backfill — newest gets
      # lowest new ID. Then populate sees newest first if we don't
      # fix the ordering.
      payload = [
        gh_commit(sha: newest_sha, parent_shas: [middle_sha]),
        gh_commit(sha: middle_sha, parent_shas: [oldest_sha]),
        gh_commit(sha: oldest_sha, parent_shas: [seed.sha])
      ]
      # Override commit_time so each is one hour apart, newest last
      payload[0][:commit][:author][:date] = base_time + 3.hours
      payload[1][:commit][:author][:date] = base_time + 2.hours
      payload[2][:commit][:author][:date] = base_time + 1.hour

      sha_to_id = Commit.ingest_payload_commits(payload)
      Commit.ingest_payload_edges(payload, sha_to_id)

      # Sanity check: newest has lower ID than oldest (the cascade trap)
      expect(sha_to_id[newest_sha]).to be < sha_to_id[oldest_sha]

      # No api fetch should fire — every commit in the chain copies
      # from its parent (oldest copies from seed; middle copies from
      # oldest; newest copies from middle).
      expect_any_instance_of(Commit).not_to receive(:api_update_test_cases)

      Commit.populate_payload_test_cases(payload, sha_to_id)

      [oldest_sha, middle_sha, newest_sha].each do |sha|
        expect(Commit.find_by(sha: sha).test_case_count).to eq(1)
      end
    end
  end

  describe Commit::TEST_SOURCE_PATTERN do
    it 'matches the do1_test_source paths in each module' do
      ['star/test_suite/do1_test_source',
       'binary/test_suite/do1_test_source',
       'astero/test_suite/do1_test_source'].each do |p|
        expect(p).to match(Commit::TEST_SOURCE_PATTERN)
      end
    end

    it 'does not match unrelated paths' do
      ['star/private/some_file.f90',
       'star/test_suite/do1_test_source_extra',
       'README.md'].each do |p|
        expect(p).not_to match(Commit::TEST_SOURCE_PATTERN)
      end
    end
  end
end
