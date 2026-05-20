source 'https://rubygems.org'
git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end
ruby '3.2.2'

gem 'rails', '~> 8.0.0'
gem 'puma', '>= 6.4.2'
gem 'puma_worker_killer'
gem 'rack', '>= 2.2.14'
gem 'rack-attack'
gem 'rack-cors', '>=2.0.2', require: 'rack/cors'
gem 'bootsnap',  '~> 1.7'
gem 'msgpack', '~>1.2'
gem 'uglifier', '>= 1.3.0'
gem 'turbolinks', '~> 5'
gem 'jbuilder', '~> 2.5'
gem 'pg'
gem "rexml", ">= 3.3.9"
gem 'bcrypt', '~> 3.1.7'
gem "net-imap", ">= 0.5.7"
gem 'nokogiri', '>= 1.18.9'
gem 'kaminari'
gem 'loofah', '~> 2.21'
gem 'lograge'
gem 'rails-html-sanitizer', '~> 1.6.2'
gem 'rubyzip', '~>1.3.0'
gem 'font-awesome-rails'

# Git stuff
gem 'octokit', "~> 4.0"
gem 'faraday-http-cache'
gem 'faraday-retry'
gem 'github_webhook', '~> 1.1'

# Frontend (Phase 4 retires these)
gem 'bootstrap', '~> 4.5'
gem 'bootstrap_form'
gem 'haml', '~> 6.1.2'
gem 'haml-rails'
gem 'high_voltage'
gem 'jquery-rails'

gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

group :development, :test do
  gem 'debug', platforms: %i[mri windows]
  gem 'capybara'
  gem 'selenium-webdriver'
  gem 'derailed'
  gem 'factory_bot_rails'
  gem 'faker'
  gem 'rspec-rails'
end

group :development do
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '~> 3.5'
  gem 'better_errors'
end

group :test do
  gem 'database_cleaner'
end
