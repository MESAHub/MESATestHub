require 'rails_helper'

RSpec.describe MorningMailer, type: :mailer do
  include ActiveSupport::Testing::TimeHelpers

  # Before the 8 AM Eastern send, so the report is built live with the
  # window ending now (after it, the window ends at 8 AM and a result
  # created "now" would fall outside it).
  around { |ex| travel_to(Time.utc(2026, 5, 25, 11)) { ex.run } }

  describe '#daily' do
    it 'renders an empty-state email when no commits were tested' do
      mail = described_class.daily

      expect(mail.subject).to match(/MESA Test Hub digest — \d{4}-\d{2}-\d{2}/)
      expect(mail.to).to eq(MorningMailer::RECIPIENTS)
      expect(mail.from).to eq(['digest@testhub.mesastar.org'])
      flat = mail.body.encoded.gsub(/\s+/, ' ')
      expect(flat).to include('No new test runs in the last 24 hours')
    end

    context 'with a tested commit on main' do
      let(:branch) { create(:branch, name: 'main') }
      let(:test_case) { create(:test_case) }
      let(:computer) { create(:computer) }
      let(:commit) { create(:commit, commit_time: 2.hours.ago,
                                     message: 'Add helium burning improvements') }

      before do
        create(:branch_membership, branch: branch, commit: commit)
        submission = create(:submission, commit: commit, computer: computer)
        create(:test_instance, commit: commit, computer: computer,
                               test_case: test_case, submission: submission)
        Rails.cache.clear
      end

      it 'renders the commit headline, branch section, and status pill' do
        body = described_class.daily.body.encoded
        # Collapse the HAML-inserted whitespace runs so we can match on
        # logical text strings instead of HTML formatting.
        flat = body.gsub(/\s+/, ' ')
        expect(flat).to include('1 commit tested in the last 24 hours')
        expect(flat).to include(commit.short_sha)
        expect(flat).to include(commit.author)
        expect(flat).to include('Add helium burning improvements')
        expect(flat).to include('main')
        expect(flat).to include('All passing')
        expect(flat).to include('Computers reporting')
      end
    end
  end
end
