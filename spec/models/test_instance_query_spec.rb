require 'rails_helper'

# Regression spec for test_instances#search query parsing and execution.
RSpec.describe TestInstance, '.query', type: :model do
  it 'parses a single key:value pair' do
    expect(TestInstance.split_query('passed: true')).to eq('passed' => 'true')
  end

  it 'parses compound key:value pairs separated by semicolons' do
    expect(TestInstance.split_query('user: Bill Wolf; passed: true'))
      .to eq('user' => 'Bill Wolf', 'passed' => 'true')
  end

  it 'runs a simple passed=true query without raising' do
    relation, failures = TestInstance.query('passed: true')
    expect { relation.to_a }.not_to raise_error
    expect(failures).to be_empty
  end

  it 'reports failures for unknown keys' do
    _, failures = TestInstance.query('nonexistent_field: anything')
    expect(failures).to include('nonexistent_field')
  end

  it 'runs a compound query without raising' do
    _, failures = TestInstance.query('passed: true; compiler: gfortran')
    expect(failures).to be_empty
  end

  it 'rejects the dropped `version:` key (no mesa_version column)' do
    _, failures = TestInstance.query('version: 10000')
    expect(failures).to include('version')
  end

  describe 'each documented search option from the help text' do
    %w[test_case commit commit_datetime passed computer user platform
       platform_version rn_RAM re_RAM threads compiler compiler_version
       runtime rn_runtime re_runtime date datetime].each do |opt|
      it "accepts #{opt} as a valid search key" do
        _, failures = TestInstance.query("#{opt}: foo")
        expect(failures).not_to include(opt),
          "search option `#{opt}` rejected — likely the column it points " \
          "to was renamed or removed"
      end
    end
  end

  def make_instance(commit:, computer:, test_case:, **attrs)
    submission = create(:submission, commit: commit, computer: computer)
    create(:test_instance, commit: commit, computer: computer,
                           test_case: test_case, submission: submission, **attrs)
  end

  describe 'commit-range filtering' do
    let(:test_case) { create(:test_case) }
    let(:computer)  { create(:computer) }
    let(:old_commit) do
      create(:commit, commit_time: Time.zone.local(2024, 1, 15))
    end
    let(:mid_commit) do
      create(:commit, commit_time: Time.zone.local(2024, 3, 15))
    end
    let(:new_commit) do
      create(:commit, commit_time: Time.zone.local(2024, 8, 15))
    end
    let!(:old_instance) do
      make_instance(commit: old_commit, computer: computer, test_case: test_case)
    end
    let!(:mid_instance) do
      make_instance(commit: mid_commit, computer: computer, test_case: test_case)
    end
    let!(:new_instance) do
      make_instance(commit: new_commit, computer: computer, test_case: test_case)
    end

    it 'narrows to commits inside a date range' do
      relation, failures = TestInstance.query(
        'commit_datetime: 2024-02-01-2024-06-30'
      )
      expect(failures).to be_empty
      expect(relation.to_a).to contain_exactly(mid_instance)
    end

    it 'matches a single commit by short SHA' do
      relation, failures = TestInstance.query(
        "commit: #{mid_commit.short_sha}"
      )
      expect(failures).to be_empty
      expect(relation.to_a).to contain_exactly(mid_instance)
    end
  end

  describe 'rn_runtime / re_runtime fields' do
    let(:test_case) { create(:test_case) }
    let(:computer)  { create(:computer) }
    let(:commit)    { create(:commit) }
    let!(:slow_instance) do
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    runtime_seconds: 800, re_time: 200,
                    total_runtime_seconds: 1000)
    end
    let!(:fast_instance) do
      make_instance(commit: commit, computer: computer, test_case: test_case,
                    runtime_seconds: 80, re_time: 20,
                    total_runtime_seconds: 100)
    end

    it 'rn_runtime filters on runtime_seconds column' do
      relation, failures = TestInstance.query('rn_runtime: 500-1000')
      expect(failures).to be_empty
      expect(relation.to_a).to contain_exactly(slow_instance)
    end

    it 're_runtime filters on re_time column' do
      relation, failures = TestInstance.query('re_runtime: 150-300')
      expect(failures).to be_empty
      expect(relation.to_a).to contain_exactly(slow_instance)
    end
  end

  describe 'empty / whitespace input' do
    it 'does not raise when query_text is empty' do
      expect { TestInstance.query('') }.not_to raise_error
    end

    it 'does not raise when query_text is whitespace only' do
      expect { TestInstance.query('   ') }.not_to raise_error
    end
  end

  describe 'runtime option' do
    it 'evaluates a runtime range query without raising' do
      # `runtime` is wired to TestInstance#total_runtime_minutes — confirm
      # that column actually exists by forcing the query to evaluate.
      relation, failures = TestInstance.query('runtime: 1-100')
      expect(failures).to be_empty
      expect { relation.to_a }.not_to raise_error
    end
  end

  describe 'unparseable date / datetime input' do
    it 'reports date parse failures instead of raising' do
      expect { TestInstance.query('date: not-a-real-date') }.not_to raise_error
    end

    it 'reports datetime parse failures instead of raising' do
      expect { TestInstance.query('datetime: not-a-real-datetime') }
        .not_to raise_error
    end
  end
end
