require 'rails_helper'

# Combined (`entire`) submissions are stored as a build row plus one row
# per test, and a result whose fingerprint is already stored is ignored
# (still answered 201, so retrying clients count it as delivered).
RSpec.describe 'Submission splitting and duplicate fingerprints', type: :request do
  let(:password) { 'pw-12345678' }
  let(:user) { create(:user, password: password, password_confirmation: password) }
  let(:computer) { create(:computer, user: user) }
  let(:branch) { create(:branch, name: 'main') }
  let(:commit) { create(:commit).tap { |c| BranchMembership.create!(branch: branch, commit: c) } }
  let!(:alpha) { create(:test_case, name: 'fake_alpha', module: 'star') }
  let!(:gamma) { create(:test_case, name: 'fake_gamma', module: 'binary') }
  let!(:tccs) { [alpha, gamma].map { |tc| TestCaseCommit.create!(commit: commit, test_case: tc) } }

  let(:submitter) { { email: user.email, password: password, computer: computer.name } }
  let(:build_info) do
    { sha: commit.sha, compiled: true, compiler: 'gfortran', compiler_version: '15.2.0',
      sdk_version: '26.3.2', math_backend: 'CRMATH' }
  end

  def instance(name, mod, outcome: 'pass')
    { test_case: name, module: mod, omp_num_threads: 4, outcome: outcome, checksum: 'abc',
      inlists: [{ inlist: 'inlist_a', runtime_minutes: 1.0 }] }
  end

  def post_submission(commit_attrs, instances: nil, fingerprints: nil)
    body = { submitter: submitter, commit: build_info.merge(commit_attrs) }
    body[:instances] = instances if instances
    body[:fingerprints] = fingerprints if fingerprints
    post '/submissions/create.json', params: body, as: :json
  end

  describe 'a combined submission' do
    let(:both) { [instance('fake_alpha', 'star'), instance('fake_gamma', 'binary', outcome: 'fail')] }

    it 'is stored as one build row plus one row per test, with scalars refreshed once' do
      create(:claim, computer: computer, commit: commit)
      expect { post_submission({ entire: true, empty: false }, instances: both) }
        .to change(Submission, :count).by(3)

      expect(response).to have_http_status(:created)
      subs = Submission.where(commit: commit).order(:id)
      expect(subs.map { |s| [s.empty, s.entire, s.compiled, s.test_instances.count] })
        .to eq([[true, false, true, 0], [false, false, nil, 1], [false, false, nil, 1]])
      expect(subs.map(&:compiler).uniq).to eq(['gfortran'])
      expect(tccs.map { |t| t.reload.slice(:passed_count, :failed_count).values }).to eq([[1, 0], [0, 1]])
      expect(commit.reload.failed_count).to eq(1)
      expect(Claim.where(commit: commit).pluck(:status)).to eq(['fulfilled'])
    end

    it 'skips results already stored and stores the rest' do
      fps = { 'build' => 'b1', 'star/fake_alpha' => 'a1', 'binary/fake_gamma' => 'g1' }
      post_submission({ empty: false }, instances: [both.first], fingerprints: fps.slice('star/fake_alpha'))

      expect { post_submission({ entire: true, empty: false }, instances: both, fingerprints: fps) }
        .to change(Submission, :count).by(2) # build + gamma; alpha was already in
      expect { post_submission({ entire: true, empty: false }, instances: both, fingerprints: fps) }
        .not_to change(Submission, :count)
      expect(response).to have_http_status(:created)
      expect(TestInstance.where(commit: commit).count).to eq(2)
    end

    it 'rolls everything back when a test case is unknown' do
      bad = both + [instance('no_such_test', 'star')]
      expect { post_submission({ entire: true, empty: false }, instances: bad) }
        .not_to change(Submission, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'duplicate fingerprints on single submissions' do
    it 'ignores a repeated build report' do
      2.times { post_submission({ empty: true }, fingerprints: { 'build' => 'b1' }) }

      expect(response).to have_http_status(:created)
      expect(Submission.where(commit: commit).count).to eq(1)
    end

    it 'ignores a repeated test result, but not a new run of the same test' do
      post_submission({ empty: false }, instances: [instance('fake_alpha', 'star')],
                                        fingerprints: { 'star/fake_alpha' => 'a1' })
      post_submission({ empty: false }, instances: [instance('fake_alpha', 'star')],
                                        fingerprints: { 'star/fake_alpha' => 'a1' })
      post_submission({ empty: false }, instances: [instance('fake_alpha', 'star')],
                                        fingerprints: { 'star/fake_alpha' => 'a2' })

      expect(TestInstance.where(commit: commit).count).to eq(2)
    end

    it 'stores repeats from clients that send no fingerprint, as before' do
      2.times { post_submission({ empty: true }) }
      expect(Submission.where(commit: commit).count).to eq(2)
    end

    it 'reports an unknown test case instead of crashing' do
      post_submission({ empty: false }, instances: [instance('no_such_test', 'star')])
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
