require 'rails_helper'

RSpec.describe BranchSyncJob, type: :job do
  include ActiveJob::TestHelper

  it 'is queued on the default queue' do
    expect { described_class.perform_later }
      .to have_enqueued_job(described_class).on_queue('default')
  end

  it 'delegates to Branch.api_update_branches when performed' do
    allow(Branch).to receive(:api_update_branches)
    described_class.new.perform
    expect(Branch).to have_received(:api_update_branches).once
  end
end
