require 'rails_helper'

# Phase C request specs for the dispatcher endpoint
# (docs/dispatcher-and-claims.md). The decision logic is covered in
# spec/services/work_dispatcher_spec.rb; these pin the HTTP contract.
RSpec.describe 'POST /api/v1/dispatch', type: :request do
  let(:user) do
    create(:user, password: 'pw-12345678', password_confirmation: 'pw-12345678')
  end
  let(:computer) { create(:computer, user: user) }
  let(:submitter) { { email: user.email, password: 'pw-12345678', computer: computer.name } }
  let(:main) { create(:branch, name: 'main') }

  let!(:commit) do
    create(:commit, commit_time: 1.hour.ago, wants_fpe: true).tap do |c|
      BranchMembership.create!(branch: main, commit: c)
      main.update!(head: c)
    end
  end

  def dispatch(body)
    post '/api/v1/dispatch', params: { submitter: submitter, dispatch: body }, as: :json
  end

  it 'recommends a commit to build, with flags, reasons, and a link' do
    dispatch(scope: 'build', can_fpe: true)

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json).to include(
      'commit_sha' => commit.sha,
      'short_sha' => commit.short_sha,
      'branch' => 'main',
      'scope' => 'build',
      'test_case_module' => nil,
      'test_case_name' => nil,
      'flags' => { 'use_full_inlists' => false, 'use_fpe' => true, 'use_converge' => false }
    )
    expect(json['reasons']).to include('[ci fpe] not yet satisfied')
    expect(json['target_url']).to end_with("/main/commits/#{commit.short_sha}")
    expect(Time.zone.parse(json['dispatched_at'])).to be_within(5.seconds).of(Time.current)
  end

  it 'recommends a test on a pinned commit, named the way the claims endpoint expects' do
    tcc = create(:test_case_commit, commit: commit,
                                    test_case: create(:test_case, name: 'wd_cool', module: 'star'))

    dispatch(scope: 'test', commit_sha: commit.sha)

    json = JSON.parse(response.body)
    expect(json).to include('scope' => 'test', 'test_case_module' => 'star',
                            'test_case_name' => 'wd_cool')
    expect(tcc).to be_present
  end

  it 'returns 204 when there is nothing to do' do
    create(:submission, commit: commit, computer: computer)
    dispatch(scope: 'build')

    expect(response).to have_http_status(:no_content)
    expect(response.body).to be_empty
  end

  it 'writes nothing to the database' do
    expect { dispatch(scope: 'build') }.not_to change(Claim, :count)
  end

  it 'rejects bad credentials' do
    submitter[:password] = 'nope'
    dispatch(scope: 'build')
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "rejects a computer the user doesn't control" do
    submitter[:computer] = create(:computer).name
    dispatch(scope: 'build')
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects an unknown scope' do
    dispatch(scope: 'everything')
    expect(response).to have_http_status(:unprocessable_content)
  end

  it 'rejects commit_sha with scope=build' do
    dispatch(scope: 'build', commit_sha: commit.sha)
    expect(response).to have_http_status(:unprocessable_content)
  end

  it '404s an unknown pinned commit' do
    dispatch(scope: 'test', commit_sha: 'f' * 40)
    expect(response).to have_http_status(:not_found)
  end
end
