require 'rails_helper'

# `format_time_tag` is the modern-view replacement for `format_time`:
# it returns a `<time>` element with three useful attributes (datetime
# / title / class) and a visible string that includes the year for
# timestamps from a prior calendar year.
#
# Defined on ApplicationController under `private`, exposed to views
# via `helper_method`. We exercise it via `send` to bypass the
# visibility check; the production callers reach it through the
# helper-method proxy, which doesn't care about ruby-level
# private/public.
RSpec.describe 'ApplicationController#format_time_tag' do
  let(:controller_class) do
    Class.new(ApplicationController) do
      def time_zone
        'Pacific Time (US & Canada)'
      end
    end
  end
  let(:controller) { controller_class.new }

  def fmt(time, **opts)
    controller.send(:format_time_tag, time, **opts)
  end

  def parse_tag(html)
    Nokogiri::HTML.fragment(html).children.first
  end

  context 'for a timestamp in the current calendar year' do
    let(:time) { Time.zone.local(Time.current.year, 5, 11, 4, 41, 17) }

    it 'returns a <time> element with the :short visible format (no year)' do
      tag = parse_tag(fmt(time))
      expect(tag.name).to eq('time')
      expect(tag.text).not_to include(time.year.to_s)
    end

    it 'sets the datetime attribute to the ISO-8601 form' do
      tag = parse_tag(fmt(time))
      expect(tag['datetime']).to eq(time.in_time_zone('Pacific Time (US & Canada)').iso8601)
    end

    it 'sets the title attribute to a full second-precision timestamp' do
      tag = parse_tag(fmt(time))
      expect(tag['title']).to match(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \S+\z/)
    end

    it 'carries the default whitespace-nowrap tabular-nums class' do
      tag = parse_tag(fmt(time))
      expect(tag['class']).to include('whitespace-nowrap', 'tabular-nums')
    end
  end

  context 'for a timestamp from a prior calendar year' do
    let(:time) { Time.zone.local(Time.current.year - 3, 5, 11, 4, 41, 17) }

    it 'includes the year in the visible text' do
      tag = parse_tag(fmt(time))
      expect(tag.text).to include((Time.current.year - 3).to_s)
    end
  end

  context 'when given nil' do
    it 'returns an empty string rather than raising' do
      expect(fmt(nil)).to eq('')
    end
  end

  context 'class override' do
    it 'accepts a custom css class through the :css keyword' do
      time = Time.zone.now
      tag = parse_tag(fmt(time, css: "text-fg-muted"))
      expect(tag['class']).to eq('text-fg-muted')
    end
  end
end
