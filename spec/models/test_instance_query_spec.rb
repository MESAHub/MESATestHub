require 'rails_helper'

# Diagnostic spec for the broken test_instances#search feature.
# Once we identify the failure mode, this stays as a regression spec.
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

  describe 'each documented search option from the help text' do
    %w[test_case passed computer user platform platform_version
       rn_RAM re_RAM threads compiler compiler_version runtime].each do |opt|
      it "accepts #{opt} as a valid search key" do
        _, failures = TestInstance.query("#{opt}: foo")
        expect(failures).not_to include(opt),
          "search option `#{opt}` rejected — likely the column it points " \
          "to was renamed or removed"
      end
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
