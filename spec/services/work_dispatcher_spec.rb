require 'rails_helper'

# Phase C scenario specs for the dispatcher's decision logic
# (docs/dispatcher-and-claims.md, "Recommendation algorithm").
RSpec.describe WorkDispatcher do
  let(:computer) { create(:computer) }
  let(:other)    { create(:computer) }
  let(:main)     { create(:branch, name: 'main') }
  let(:feature)  { create(:branch, name: 'feature-x') }

  # A commit `age` old on `branch`, which also becomes (or stays) the
  # branch head if it's the newest commit on it.
  def commit_on(branch, age: 1.hour, **attrs)
    commit = create(:commit, commit_time: age.ago, **attrs)
    BranchMembership.create!(branch: branch, commit: commit)
    if branch.head.nil? || branch.head.commit_time < commit.commit_time
      branch.update!(head: commit)
    end
    commit
  end

  def dispatch(scope: 'build', commit: nil, **capabilities)
    described_class.new(computer: computer, scope: scope, commit: commit,
                        capabilities: capabilities).call
  end

  describe 'build scope' do
    it 'returns nil when nothing is eligible' do
      expect(dispatch).to be_nil
    end

    it 'prefers a fresh commit on main over an older feature-branch commit' do
      old_feature = commit_on(feature, age: 5.days)
      fresh_main  = commit_on(main, age: 1.hour)

      rec = dispatch
      expect(rec.commit).to eq(fresh_main)
      expect(rec.scope).to eq('build')
      expect(rec.test_case_commit).to be_nil
      expect(rec.flags).to eq(full_inlists: false, fpe: false, converge: false)
      expect(rec.reasons).to include('on main')
      expect(old_feature).to be_present
    end

    it 'demotes commits other computers already cover' do
      covered   = commit_on(main, age: 1.hour)
      uncovered = commit_on(main, age: 2.hours)
      create(:submission, commit: covered, computer: other)

      expect(dispatch.commit).to eq(uncovered)
    end

    it 'counts another computer\'s pending build claim as coverage' do
      claimed   = commit_on(main, age: 1.hour)
      unclaimed = commit_on(main, age: 2.hours)
      create(:claim, commit: claimed, computer: other)

      expect(dispatch.commit).to eq(unclaimed)
    end

    it 'never re-recommends a commit this computer already submitted on or claimed' do
      submitted = commit_on(main, age: 1.hour)
      claimed   = commit_on(main, age: 2.hours)
      create(:submission, commit: submitted, computer: computer)
      create(:claim, commit: claimed, computer: computer)

      expect(dispatch).to be_nil
    end

    it 'skips a commit this computer let a build claim expire on without submitting' do
      abandoned = commit_on(main, age: 1.hour)
      fallback  = commit_on(main, age: 3.days)
      create(:claim, :expired, commit: abandoned, computer: computer)

      expect(dispatch.commit).to eq(fallback)
    end

    it 'un-blocklists the commit once a late submission fulfills the claim' do
      commit = commit_on(main, age: 1.hour)
      claim = create(:claim, :expired, commit: commit, computer: computer)
      create(:submission, commit: create(:commit), computer: computer, claim: claim)

      expect(dispatch.commit).to eq(commit)
    end

    it 'skips [ci skip] commits, stale commits, and commits only on inactive branches' do
      commit_on(main, age: 1.hour, ci_skip: true)
      commit_on(main, age: 45.days)
      merged = create(:branch, name: 'merged-x', merged: true)
      commit_on(merged, age: 1.hour)
      stale_branch = create(:branch, name: 'stale-x')
      old_head = commit_on(stale_branch, age: 120.days)
      # Recent commit whose only branch has a head older than 90 days
      # can't happen in practice; fake it to isolate the branch rule.
      recent = create(:commit, commit_time: 1.hour.ago)
      BranchMembership.create!(branch: stale_branch, commit: recent)
      expect(stale_branch.reload.head).to eq(old_head)

      expect(dispatch).to be_nil
    end

    it 'boosts an unmet [ci fpe] request only for computers that can run FPE checks' do
      plain = commit_on(main, age: 1.hour)
      fpe   = commit_on(main, age: 2.days, wants_fpe: true)

      expect(dispatch.commit).to eq(plain)

      rec = dispatch(fpe: true)
      expect(rec.commit).to eq(fpe)
      expect(rec.flags[:fpe]).to be true
      expect(rec.reasons).to include('[ci fpe] not yet satisfied')
    end

    it 'stops boosting a request once it is satisfied' do
      plain = commit_on(main, age: 1.hour)
      commit_on(main, age: 2.days, wants_full_inlists: true,
                      full_inlists_satisfied_at: 1.hour.ago)

      rec = dispatch(full_inlists: true)
      expect(rec.commit).to eq(plain)
      expect(rec.flags[:full_inlists]).to be false
    end
  end

  describe 'test scope' do
    let(:commit) { commit_on(main, age: 1.hour) }
    let!(:tcc_a) { create(:test_case_commit, commit: commit, test_case: create(:test_case, name: 'a_test')) }
    let!(:tcc_b) { create(:test_case_commit, commit: commit, test_case: create(:test_case, name: 'b_test')) }

    def run!(tcc, on: computer, **attrs)
      sub = create(:submission, commit: tcc.commit, computer: on, entire: false)
      create(:test_instance, commit: tcc.commit, computer: on, test_case: tcc.test_case,
                             test_case_commit: tcc, submission: sub, **attrs)
    end

    it 'only considers commits this computer has built when no commit is pinned' do
      expect(dispatch(scope: 'test')).to be_nil

      create(:submission, commit: commit, computer: computer, empty: true, entire: false)
      expect(dispatch(scope: 'test').commit).to eq(commit)
    end

    it 'does not count a failed build as built' do
      create(:submission, commit: commit, computer: computer, empty: true, entire: false,
                          compiled: false)
      expect(dispatch(scope: 'test')).to be_nil
    end

    it 'picks the test fewest computers have run, skipping ones it ran or claimed' do
      run!(tcc_a, on: other)
      rec = dispatch(scope: 'test', commit: commit)
      expect(rec.test_case_commit).to eq(tcc_b)

      create(:claim, :test_scope, commit: commit, computer: computer, test_case_commit: tcc_b)
      expect(dispatch(scope: 'test', commit: commit).test_case_commit).to eq(tcc_a)

      run!(tcc_a)
      expect(dispatch(scope: 'test', commit: commit)).to be_nil
    end

    it 'skips a test whose claim this computer abandoned' do
      create(:claim, :test_scope, :expired, commit: commit, computer: computer,
                                            test_case_commit: tcc_a)
      expect(dispatch(scope: 'test', commit: commit).test_case_commit).to eq(tcc_b)
    end

    it 'asks for a full-inlists rerun of a test that has only had default runs' do
      commit.update!(wants_full_inlists: true)
      run!(tcc_a)
      run!(tcc_b)
      run!(tcc_b, on: other, run_optional: true)

      rec = dispatch(scope: 'test', commit: commit, full_inlists: true)
      expect(rec.test_case_commit).to eq(tcc_a)
      expect(rec.flag_params).to eq(use_full_inlists: true, use_fpe: false, use_converge: false)
      expect(rec.reasons).to include('[ci optional] not yet run for this test')

      # A computer that can't do full inlists has nothing left here.
      expect(dispatch(scope: 'test', commit: commit)).to be_nil
    end

    it 'treats a pending full-inlists claim as covering the request' do
      commit.update!(wants_full_inlists: true)
      run!(tcc_a)
      run!(tcc_b)
      create(:claim, :test_scope, commit: commit, computer: other, test_case_commit: tcc_a,
                                  use_full_inlists: true)

      rec = dispatch(scope: 'test', commit: commit, full_inlists: true)
      expect(rec.test_case_commit).to eq(tcc_b)
    end

    it 'moves on to the next built commit when the best one is exhausted' do
      older = commit_on(main, age: 2.days)
      older_tcc = create(:test_case_commit, commit: older)
      create(:submission, commit: older, computer: computer, empty: true, entire: false)
      run!(tcc_a)
      run!(tcc_b)

      rec = dispatch(scope: 'test')
      expect(rec.commit).to eq(older)
      expect(rec.test_case_commit).to eq(older_tcc)
    end
  end

  it 'rejects a pinned commit for build scope' do
    expect { described_class.new(computer: computer, scope: 'build', commit: create(:commit)) }
      .to raise_error(ArgumentError)
  end
end
