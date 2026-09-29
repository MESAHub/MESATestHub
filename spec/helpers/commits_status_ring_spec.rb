require 'rails_helper'

RSpec.describe CommitsHelper, type: :helper do
  def state(build: :all_ok, has_pending: false, **tests)
    base = { uniform_failing_tests: 0, fpe_tests: 0, mixed_tests: 0, checksum_tests: 0, checksum_passing_tests: 0,
             clean_passing_tests: 0, reported_tests: 0, total_tests: 0, has_pending: has_pending }
    { build: { status: build }, tests: base.merge(tests) }
  end

  describe '#status_ring_data' do
    it 'lists present statuses worst-first, one arc each regardless of count' do
      data = helper.status_ring_data(state(clean_passing_tests: 100, uniform_failing_tests: 2,
                                           checksum_passing_tests: 1, reported_tests: 103, total_tests: 103))
      expect(data[:segments]).to eq(%i[fail checksum pass])
      expect(data[:coverage]).to eq(1.0)
    end

    it 'reports partial coverage while tests are unreported' do
      data = helper.status_ring_data(state(clean_passing_tests: 60, reported_tests: 60, total_tests: 100))
      expect(data[:segments]).to eq(%i[pass])
      expect(data[:coverage]).to eq(0.6)
    end

    it 'has no segments and zero coverage for an untested commit' do
      data = helper.status_ring_data(state(total_tests: 100))
      expect(data).to eq(segments: [], coverage: 0.0)
    end
  end

  describe '#commit_status_ring' do
    it 'draws a closed ring for a single complete status' do
      html = helper.commit_status_ring(state(clean_passing_tests: 5, reported_tests: 5, total_tests: 5))
      expect(html).not_to include('stroke-dasharray')
      expect(html).not_to include('<path')
    end

    it 'draws one arc per status plus an open gap when incomplete' do
      html = helper.commit_status_ring(state(clean_passing_tests: 97, mixed_tests: 1,
                                             reported_tests: 98, total_tests: 100))
      expect(html.scan('<path').size).to eq(2)
      expect(html).to include('stroke-dasharray')
    end

    it 'colors the unreported gap blue while work is pending' do
      html = helper.commit_status_ring(state(has_pending: true, clean_passing_tests: 1,
                                             reported_tests: 1, total_tests: 10))
      expect(html).to include('var(--color-info)')
    end

    it 'labels the ring with counts worst-first' do
      label = helper.status_ring_label(state(uniform_failing_tests: 2, clean_passing_tests: 98,
                                             reported_tests: 100, total_tests: 100))
      expect(label).to eq('build: all built · 2 failing · 98 passing · 100/100 tests reported')
    end
  end
end
