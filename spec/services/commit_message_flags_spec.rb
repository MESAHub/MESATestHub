require 'rails_helper'

# CommitMessageFlags parses the four CI directive flags out of a
# commit message body. Called from Commit.hash_from_github at
# ingest, so every column it returns must agree with what the
# legacy Commit#ci_*? predicates report on the same message — the
# Postgres backfill in the migration also derives from the same
# regex shapes, so this spec doubles as the contract for that
# backfill.
RSpec.describe CommitMessageFlags do
  describe '.parse' do
    let(:default_flags) do
      {
        ci_skip: false,
        wants_full_inlists: false,
        wants_fpe: false,
        wants_converge: false
      }
    end

    it 'returns all-false for an empty message' do
      expect(described_class.parse('')).to eq(default_flags)
    end

    it 'returns all-false for a nil message' do
      expect(described_class.parse(nil)).to eq(default_flags)
    end

    it 'returns all-false for a plain message with no directives' do
      expect(described_class.parse("Fix a typo in the README"))
        .to eq(default_flags)
    end

    it 'recognizes [ci skip] in isolation' do
      result = described_class.parse("Bump version [ci skip]")
      expect(result[:ci_skip]).to be true
      expect(result[:wants_full_inlists]).to be false
      expect(result[:wants_fpe]).to be false
      expect(result[:wants_converge]).to be false
    end

    it 'recognizes [ci optional]' do
      result = described_class.parse("Refactor [ci optional]")
      expect(result[:wants_full_inlists]).to be true
      expect(result[:ci_skip]).to be false
    end

    it 'recognizes [ci optional 1234] (with digit count)' do
      result = described_class.parse("Refactor [ci optional 1234]")
      expect(result[:wants_full_inlists]).to be true
    end

    it 'recognizes [ci fpe]' do
      result = described_class.parse("Fix conv [ci fpe]")
      expect(result[:wants_fpe]).to be true
    end

    it 'recognizes [ci converge]' do
      result = described_class.parse("Tune solver [ci converge]")
      expect(result[:wants_converge]).to be true
    end

    it 'recognizes multiple directives in the same message' do
      result = described_class.parse("Big change [ci fpe] [ci converge]")
      expect(result[:wants_fpe]).to be true
      expect(result[:wants_converge]).to be true
      expect(result[:wants_full_inlists]).to be false
      expect(result[:ci_skip]).to be false
    end

    it 'suppresses ci_skip when ci optional also appears' do
      # Merge commits that fold a `[ci skip]` PR into something that
      # asked for full inlists shouldn't skip testing — the optional
      # directive wins.
      result = described_class.parse("Merge: tidy [ci skip] [ci optional]")
      expect(result[:ci_skip]).to be false
      expect(result[:wants_full_inlists]).to be true
    end

    it 'suppresses ci_skip when ci fpe also appears' do
      result = described_class.parse("Merge: tidy [ci skip] [ci fpe]")
      expect(result[:ci_skip]).to be false
      expect(result[:wants_fpe]).to be true
    end

    it 'does NOT suppress ci_skip when only ci converge accompanies it' do
      # Matches the legacy behavior in Commit#ci_skip? — `[ci converge]`
      # is not part of the suppression set.
      result = described_class.parse("Tidy [ci skip] [ci converge]")
      expect(result[:ci_skip]).to be true
      expect(result[:wants_converge]).to be true
    end

    it 'tolerates extra whitespace inside the brackets' do
      result = described_class.parse("Whitespace [  ci   skip  ]")
      expect(result[:ci_skip]).to be true
    end

    it 'tolerates extra whitespace in [ci optional N]' do
      result = described_class.parse("Long [ ci   optional   42 ]")
      expect(result[:wants_full_inlists]).to be true
    end

    it 'is case-sensitive (matches the legacy regex behavior)' do
      # The legacy Commit#ci_skip? was case-sensitive on `ci skip`;
      # preserve that — if MESA developers ever need case-insensitive,
      # it's a deliberate change.
      expect(described_class.parse("[CI SKIP]")[:ci_skip]).to be false
    end

    it 'ignores [ci skip] inside an unrelated word' do
      # Bracketed form is the only one recognized; bare "ci skip" in
      # prose shouldn't trigger.
      expect(described_class.parse("we should ci skip this")[:ci_skip])
        .to be false
    end

    describe 'first-line restriction' do
      # MESA convention places directives in the subject line of
      # the commit they apply to. Squash/merge commits routinely
      # include each squashed commit's subject in the body — if we
      # scanned the whole message we'd inherit every directive
      # from every constituent commit, which is exactly the
      # opposite of what the author intended.
      it 'ignores [ci skip] that appears only in the message body' do
        msg = "docs: Document MESA branching model\n\n" \
              "Misc cleanup [ci skip]\n"
        result = described_class.parse(msg)
        expect(result[:ci_skip]).to be false
      end

      it 'ignores [ci fpe] / [ci optional] / [ci converge] in the body' do
        msg = "Refactor public API\n\n" \
              "* Tighten ABI [ci fpe]\n" \
              "* New solver path [ci optional]\n" \
              "* Tune step ctrl [ci converge]\n"
        result = described_class.parse(msg)
        expect(result[:wants_fpe]).to be false
        expect(result[:wants_full_inlists]).to be false
        expect(result[:wants_converge]).to be false
      end

      it 'still recognizes a directive on the first line of a multi-line message' do
        msg = "Fix conv [ci fpe]\n\n" \
              "Lots of further detail in the body that doesn't matter."
        result = described_class.parse(msg)
        expect(result[:wants_fpe]).to be true
      end

      it 'handles squash/merge bodies that bundle many subject lines' do
        msg = "Merge feature-X (#42)\n\n" \
              "* Tidy [ci skip]\n" \
              "* Solver swap [ci fpe]\n" \
              "* RTI tune [ci converge]\n" \
              "* All-inlists pass [ci optional]\n"
        result = described_class.parse(msg)
        expect(result).to eq(
          ci_skip: false,
          wants_full_inlists: false,
          wants_fpe: false,
          wants_converge: false
        )
      end

      it 'recognizes a directive only on the first line, even with CRLF endings' do
        msg = "Refactor [ci optional]\r\nfollow-on body\r\n"
        result = described_class.parse(msg)
        expect(result[:wants_full_inlists]).to be true
      end
    end
  end
end
