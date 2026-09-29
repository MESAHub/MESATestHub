require 'rails_helper'

RSpec.describe ChecksumComparison do
  let(:computers) { Array.new(4) { |i| build_stubbed(:computer, id: 100 + i) } }

  def inst(computer: computers[0], checksum: 'aaa', **attrs)
    build_stubbed(:test_instance, computer: computer, checksum: checksum,
                                  inlist_count: 3, **attrs)
  end

  def compare(*instances)
    described_class.new(instances)
  end

  describe 'grouping' do
    it 'agrees when every comparable instance matches' do
      c = compare(inst, inst(computer: computers[1]))
      expect(c.max_distinct).to eq(1)
      expect(c).not_to be_mismatch
    end

    it 'does not compare runs that ran a different number of inlists' do
      # A full run of a test with optional inlists ends on a different
      # model than a default run; that's expected, not a mismatch.
      c = compare(inst(checksum: 'aaa', inlist_count: 3),
                  inst(computer: computers[1], checksum: 'bbb', inlist_count: 5, run_optional: true))
      expect(c).not_to be_mismatch
    end

    it 'compares full runs with each other' do
      c = compare(inst(checksum: 'aaa', inlist_count: 5, run_optional: true),
                  inst(computer: computers[1], checksum: 'bbb', inlist_count: 5, run_optional: true))
      expect(c).to be_mismatch
    end

    it 'compares a full run with a default run when they ran the same inlists' do
      # Tests without optional inlists run identically either way.
      c = compare(inst(checksum: 'aaa', run_optional: false),
                  inst(computer: computers[1], checksum: 'bbb', run_optional: true))
      expect(c).to be_mismatch
    end

    it 'pools SDK versions together' do
      c = compare(inst(checksum: 'aaa', sdk_version: '24.7.1'),
                  inst(computer: computers[1], checksum: 'bbb', sdk_version: '25.12.1'))
      expect(c).to be_mismatch
    end

    it 'does not compare SDK builds against non-SDK builds' do
      c = compare(inst(checksum: 'aaa', sdk_version: '25.12.1'),
                  inst(computer: computers[1], checksum: 'bbb', sdk_version: nil, compiler: 'ifort'))
      expect(c).not_to be_mismatch
    end

    it 'falls back to run_optional when inlist_count is missing' do
      c = compare(inst(checksum: 'aaa', inlist_count: nil, run_optional: false),
                  inst(computer: computers[1], checksum: 'bbb', inlist_count: nil, run_optional: true))
      expect(c).not_to be_mismatch
    end
  end

  describe 'exclusions' do
    it 'ignores FPE-checking runs' do
      c = compare(inst(checksum: 'aaa'), inst(computer: computers[1], checksum: 'bbb', fpe_checks: true))
      expect(c).not_to be_mismatch
    end

    it 'ignores non-standard resolution in either direction' do
      c = compare(inst(checksum: 'aaa'),
                  inst(computer: computers[1], checksum: 'bbb', resolution_factor: 0.5),
                  inst(computer: computers[2], checksum: 'ccc', resolution_factor: 2.0))
      expect(c).not_to be_mismatch
    end

    it 'ignores failing instances' do
      c = compare(inst(checksum: 'aaa'), inst(computer: computers[1], checksum: 'bbb', passed: false))
      expect(c).not_to be_mismatch
    end

    it 'ignores blank and placeholder checksums' do
      c = compare(inst(checksum: 'aaa'),
                  inst(computer: computers[1], checksum: ''),
                  inst(computer: computers[2], checksum: nil),
                  inst(computer: computers[3], checksum: '0' * 32))
      expect(c.max_distinct).to eq(1)
    end

    it 'reports zero when nothing is comparable' do
      expect(compare(inst(fpe_checks: true)).max_distinct).to eq(0)
    end
  end

  describe '#disagrees?' do
    it 'flags only the instances off the plurality checksum' do
      majority = computers.first(3).map { |c| inst(computer: c, checksum: 'aaa') }
      outlier = inst(computer: computers[3], checksum: 'bbb')
      c = compare(*majority, outlier)

      expect(c.disagrees?(outlier)).to be true
      expect(majority.none? { |i| c.disagrees?(i) }).to be true
    end

    it 'flags everyone when there is no plurality' do
      a = inst(checksum: 'aaa')
      b = inst(computer: computers[1], checksum: 'bbb')
      c = compare(a, b)
      expect([c.disagrees?(a), c.disagrees?(b)]).to eq([true, true])
    end

    it 'counts votes by computer, not by resubmission' do
      # One computer resubmitting the same checksum three times doesn't
      # outvote a second computer.
      repeats = Array.new(3) { inst(computer: computers[0], checksum: 'aaa') }
      other = inst(computer: computers[1], checksum: 'bbb')
      c = compare(*repeats, other)
      expect(c.disagrees?(other)).to be true
      expect(repeats.all? { |i| c.disagrees?(i) }).to be true
    end

    it 'never flags excluded instances' do
      fpe = inst(computer: computers[2], checksum: 'zzz', fpe_checks: true)
      c = compare(inst(checksum: 'aaa'), inst(computer: computers[1], checksum: 'bbb'), fpe)
      expect(c.disagrees?(fpe)).to be false
    end
  end

  describe '#match_counts' do
    it 'counts computers in the group sharing the checksum' do
      a = inst(computer: computers[0], checksum: 'aaa')
      b = inst(computer: computers[1], checksum: 'aaa')
      d = inst(computer: computers[2], checksum: 'bbb')
      c = compare(a, b, d)
      expect(c.match_counts(a)).to eq(count: 2, total: 3)
      expect(c.match_counts(d)).to eq(count: 1, total: 3)
    end

    it 'is nil for instances outside any comparison' do
      fpe = inst(fpe_checks: true)
      expect(compare(fpe).match_counts(fpe)).to be_nil
    end
  end

  describe '#conflicting_checksums' do
    it 'lists checksums from mismatched groups only' do
      c = compare(inst(checksum: 'aaa'), inst(computer: computers[1], checksum: 'bbb'),
                  inst(computer: computers[2], checksum: 'ccc', inlist_count: 5))
      expect(c.conflicting_checksums).to contain_exactly('aaa', 'bbb')
    end
  end
end
