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
gem 'bootsnap', '~> 1.18'
gem 'msgpack', '~> 1.7'
gem 'jbuilder', '~> 2.13'
gem 'pg'
gem "rexml", ">= 3.3.9"
gem 'bcrypt', '~> 3.1.7'
gem "net-imap", ">= 0.5.7"
gem 'nokogiri', '>= 1.18.9'
gem 'kaminari'
gem 'loofah', '~> 2.21'
gem 'lograge'
gem 'rails-html-sanitizer', '~> 1.6.2'

# Git stuff
gem 'octokit', '~> 10.0'
gem 'faraday-http-cache'
gem 'faraday-retry'
gem 'github_webhook', '~> 1.4'

# Frontend stack. Tailwind for styling, Turbo + Stimulus for
# behavior, Importmap for ES module loading without a JS build
# step. HAML is the template engine. Sprockets-rails serves the
# Tailwind build at app/assets/builds/tailwind.css and wires the
# tailwindcss-rails build hook into assets:precompile at deploy.
gem 'haml', '~> 6.1.2'
gem 'haml-rails'
gem 'sprockets-rails'
gem 'tailwindcss-rails', '~> 4.0'
gem 'turbo-rails', '~> 2.0'
gem 'stimulus-rails', '~> 1.3'
gem 'importmap-rails', '~> 2.0'

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
