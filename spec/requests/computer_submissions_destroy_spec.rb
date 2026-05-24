require 'rails_helper'

RSpec.describe 'Bulk-deleting submissions on computers#show', type: :request do
  let(:password) { 'correct-horse' }
  let(:owner) { create(:user, password: password, password_confirmation: password) }
  let(:other_user) { create(:user, password: password, password_confirmation: password) }
  let(:admin) { create(:user, :admin, password: password, password_confirmation: password) }
  let(:computer) { create(:computer, user: owner) }
  let(:other_computer) { create(:computer, user: other_user) }

  let!(:submissions) { create_list(:submission, 3, computer: computer) }
  let!(:other_submission) { create(:submission, computer: other_computer) }

  def sign_in(user)
    post '/sessions', params: { email: user.email, password: password }
  end

  def destroy_path(comp = computer)
    "/users/#{comp.user_id}/computers/#{comp.id}/submissions"
  end

  describe 'authorization' do
    it 'redirects an unauthenticated request to login' do
      delete destroy_path, params: { submission_ids: [submissions.first.id] }
      expect(response).to redirect_to(login_url)
      expect(Submission.exists?(submissions.first.id)).to be true
    end

    it 'forbids a non-owner non-admin from deleting submissions on this computer' do
      sign_in(other_user)
      delete destroy_path, params: { submission_ids: [submissions.first.id] }
      # authorize_self_or_admin redirects to login_url with an alert
      expect(response).to redirect_to(login_url)
      expect(Submission.exists?(submissions.first.id)).to be true
    end

    it 'lets the owning user delete their own computer’s submissions' do
      sign_in(owner)
      expect do
        delete destroy_path, params: { submission_ids: [submissions.first.id] }
      end.to change { computer.submissions.count }.by(-1)
      expect(response).to redirect_to(user_computer_path(owner, computer))
      expect(flash[:notice]).to match(/Deleted 1 submission/)
    end

    it 'lets an admin delete from any computer' do
      sign_in(admin)
      expect do
        delete destroy_path, params: { submission_ids: submissions.map(&:id) }
      end.to change { computer.submissions.count }.by(-3)
      expect(response).to redirect_to(user_computer_path(owner, computer))
    end
  end

  describe 'IDOR protection' do
    before { sign_in(owner) }

    it 'silently drops IDs that belong to a different computer' do
      # owner submits other_computer's submission ID alongside their own.
      # The scope is rooted at @computer.submissions, so only the
      # owned submission is destroyed.
      expect do
        delete destroy_path,
               params: { submission_ids: [submissions.first.id, other_submission.id] }
      end.to change { Submission.count }.by(-1)
      expect(Submission.exists?(other_submission.id)).to be true
      expect(Submission.exists?(submissions.first.id)).to be false
    end

    it 'rejects an attempt to POST to another user’s computer URL' do
      delete destroy_path(other_computer),
             params: { submission_ids: [other_submission.id] }
      # owner isn't self_or_admin of other_user, so authorize redirects
      expect(response).to redirect_to(login_url)
      expect(Submission.exists?(other_submission.id)).to be true
    end
  end

  describe 'edge cases' do
    before { sign_in(owner) }

    it 'returns an alert when no submission_ids are supplied' do
      delete destroy_path
      expect(response).to redirect_to(user_computer_path(owner, computer))
      expect(flash[:alert]).to match(/No submissions selected/)
    end

    it 'returns an alert when supplied IDs match nothing on this computer' do
      delete destroy_path, params: { submission_ids: [other_submission.id] }
      expect(response).to redirect_to(user_computer_path(owner, computer))
      expect(flash[:alert]).to match(/No matching submissions/)
    end

    it 'caps bulk deletion at BULK_DESTROY_LIMIT' do
      stub_const('ComputersController::BULK_DESTROY_LIMIT', 2)
      expect do
        delete destroy_path, params: { submission_ids: submissions.map(&:id) }
      end.not_to(change { Submission.count })
      expect(flash[:alert]).to match(/Cannot delete more than 2/)
    end
  end

  describe 'select_all_matching with active filter' do
    let!(:branchy_commit) { create(:commit, sha: 'aaaa1234' + 'b' * 32) }
    let!(:matching_sub_a) { create(:submission, computer: computer, commit: branchy_commit) }
    let!(:matching_sub_b) { create(:submission, computer: computer, commit: branchy_commit) }

    before { sign_in(owner) }

    it 'deletes everything matching the filter when select_all_matching=1' do
      expect do
        delete destroy_path,
               params: { select_all_matching: '1', sha: 'aaaa1234' }
      end.to change { computer.submissions.count }.by(-2)
      expect(Submission.exists?(matching_sub_a.id)).to be false
      expect(Submission.exists?(matching_sub_b.id)).to be false
      # The 3 unfiltered factory submissions on this computer survive.
      expect(computer.reload.submissions.count).to eq(3)
    end

    it 'never crosses computer boundaries even with select_all_matching' do
      # other_submission also exists, but it's on a different computer.
      # With the filter scope rooted at @computer, it's unreachable.
      delete destroy_path, params: { select_all_matching: '1' }
      expect(Submission.exists?(other_submission.id)).to be true
    end

    it 'preserves the filter params on the redirect' do
      delete destroy_path, params: { select_all_matching: '1', sha: 'aaaa1234' }
      expect(response.location).to include("sha=aaaa1234")
    end
  end

  describe 'GET /users/:user_id/computers/:id with filter params' do
    let!(:old_commit) { create(:commit, sha: 'feedbeef' + 'c' * 32) }
    let!(:old_sub)    { create(:submission, computer: computer, commit: old_commit,
                               created_at: 2.years.ago) }
    let!(:new_sub)    { create(:submission, computer: computer, created_at: 1.day.ago) }

    before { sign_in(owner) }

    it 'filters by SHA prefix' do
      get "/users/#{owner.id}/computers/#{computer.id}",
          params: { sha: 'feedbeef' }
      expect(response.body).to include(old_sub.commit.short_sha)
      expect(response.body).not_to include(new_sub.commit.short_sha)
    end

    it 'filters by date range (inclusive bounds)' do
      get "/users/#{owner.id}/computers/#{computer.id}",
          params: { from: 7.days.ago.to_date.to_s }
      # new_sub (1 day ago) should appear; old_sub (2 years ago) shouldn't
      expect(response.body).to include(new_sub.commit.short_sha)
      expect(response.body).not_to include(old_sub.commit.short_sha)
    end

    it 'returns the empty-filter state when the filter matches nothing' do
      get "/users/#{owner.id}/computers/#{computer.id}",
          params: { sha: '0000notreal' }
      expect(response.body).to include('No submissions match the current filter')
    end

    it 'returns a junk-date filter as no filter rather than 500' do
      # Date.parse on garbage raises; our parser swallows the exception.
      get "/users/#{owner.id}/computers/#{computer.id}",
          params: { from: 'not-a-date' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'type filter' do
    let!(:empty_sub)      { create(:submission, computer: computer, empty: true,  entire: false) }
    let!(:individual_sub) { create(:submission, computer: computer, empty: false, entire: false) }
    let!(:combined_sub)   { create(:submission, computer: computer, empty: false, entire: true) }

    before { sign_in(owner) }

    it 'filters to empty (build-only) submissions' do
      get "/users/#{owner.id}/computers/#{computer.id}", params: { type: 'empty' }
      shas = response.body.scan(/[a-f0-9]{7}/).uniq
      expect(shas).to include(empty_sub.commit.short_sha)
      expect(shas).not_to include(individual_sub.commit.short_sha)
      expect(shas).not_to include(combined_sub.commit.short_sha)
    end

    it 'filters to individual-test submissions' do
      get "/users/#{owner.id}/computers/#{computer.id}", params: { type: 'individual' }
      shas = response.body.scan(/[a-f0-9]{7}/).uniq
      expect(shas).to include(individual_sub.commit.short_sha)
      expect(shas).not_to include(empty_sub.commit.short_sha)
      expect(shas).not_to include(combined_sub.commit.short_sha)
    end

    it 'filters to combined (build + suite) submissions' do
      get "/users/#{owner.id}/computers/#{computer.id}", params: { type: 'combined' }
      shas = response.body.scan(/[a-f0-9]{7}/).uniq
      expect(shas).to include(combined_sub.commit.short_sha)
      expect(shas).not_to include(empty_sub.commit.short_sha)
      expect(shas).not_to include(individual_sub.commit.short_sha)
    end

    it 'treats a junk type param as no filter' do
      get "/users/#{owner.id}/computers/#{computer.id}", params: { type: 'banana' }
      expect(response).to have_http_status(:ok)
      shas = response.body.scan(/[a-f0-9]{7}/).uniq
      expect(shas).to include(empty_sub.commit.short_sha)
      expect(shas).to include(individual_sub.commit.short_sha)
      expect(shas).to include(combined_sub.commit.short_sha)
    end

    it 'narrows destroy to the type-matching subset' do
      expect do
        delete destroy_path,
               params: { select_all_matching: '1', type: 'empty' }
      end.to change { computer.submissions.count }.by(-1)
      expect(Submission.exists?(empty_sub.id)).to be false
      expect(Submission.exists?(individual_sub.id)).to be true
      expect(Submission.exists?(combined_sub.id)).to be true
    end

    it 'preserves type on the post-delete redirect' do
      delete destroy_path,
             params: { select_all_matching: '1', type: 'empty' }
      expect(response.location).to include("type=empty")
    end
  end
end
