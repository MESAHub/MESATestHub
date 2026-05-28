require 'rails_helper'

# Catches breakage in the Octokit middleware stack wired up at the top of
# app/models/application_record.rb. Doesn't hit the network — these specs
# only verify that the constants and the Faraday RackBuilder configuration
# are intact, which is the kind of thing a major Octokit bump can silently
# break.
RSpec.describe 'GitHub API client wiring' do
  it 'exposes an Octokit::Client through ApplicationRecord.api' do
    expect(ApplicationRecord.api).to be_an(Octokit::Client)
  end

  it 'exposes a non-auto-paginating client variant' do
    expect(ApplicationRecord.api(auto_paginate: false)).to be_an(Octokit::Client)
  end

  it 'returns the same auto-paginating client on repeated calls' do
    expect(ApplicationRecord.api).to equal(ApplicationRecord.api)
  end

  it 'uses MESAHub/mesa as the repo path' do
    expect(ApplicationRecord.repo_path).to eq('MESAHub/mesa')
  end

  it 'configures the Octokit middleware with Retry, Faraday::HttpCache, and Octokit::Response::RaiseError' do
    handler_classes = Octokit.middleware.handlers.map(&:klass)
    expect(handler_classes).to include(Faraday::Retry::Middleware)
    expect(handler_classes).to include(Faraday::HttpCache)
    expect(handler_classes).to include(Octokit::Response::RaiseError)
  end

  it 'places Faraday::Retry outermost so it catches Octokit exceptions raised by RaiseError' do
    handler_classes = Octokit.middleware.handlers.map(&:klass)
    retry_idx = handler_classes.index(Faraday::Retry::Middleware)
    raise_idx = handler_classes.index(Octokit::Response::RaiseError)
    expect(retry_idx).to be < raise_idx
  end

  it 'still has Octokit::NotFound available for rescue clauses' do
    expect(defined?(Octokit::NotFound)).to eq('constant')
    expect(Octokit::NotFound.ancestors).to include(StandardError)
  end

  it 'Commit.api delegates to the same client (Commit inherits from ApplicationRecord)' do
    expect(Commit.api).to equal(ApplicationRecord.api)
    expect(Branch.api).to equal(ApplicationRecord.api)
  end
end
