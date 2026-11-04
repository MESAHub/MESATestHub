require 'rails_helper'

RSpec.describe MorningMailerHelper, type: :helper do
  describe '#mailer_anomaly_url' do
    let(:test_case) { create(:test_case, name: 'make_zams', module: 'star') }
    let(:computer) { create(:computer, name: 'BOSE') }
    let(:commit) { create(:commit) }
    let(:ti) do
      create(:test_instance, test_case: test_case, computer: computer, commit: commit,
                             submission: create(:submission, commit: commit, computer: computer))
    end

    def anomaly(metric:, branch:)
      MorningReport::Anomaly.new(test_instance: ti, metric: metric, link_branch_name: branch)
    end

    it 'opens the Trend tab on the branch, centered on the commit, plotting the metric' do
      uri = URI.parse(helper.mailer_anomaly_url(anomaly(metric: :re_mem, branch: 'main')))
      query = Rack::Utils.parse_query(uri.query)

      expect(uri.path).to eq('/main/test_cases/star/make_zams')
      expect(query).to include('tab' => 'trend', 'metric' => 'mem_re',
                               'center' => commit.sha, 'computer' => 'BOSE')
    end

    it 'falls back to the search page for a commit on no branch' do
      url = helper.mailer_anomaly_url(anomaly(metric: :runtime, branch: nil))
      expect(URI.parse(url).path).to eq(search_instances_path)
    end
  end
end
