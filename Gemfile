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
gem 'terser', '~> 1.2'
gem 'turbolinks', '~> 5'
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
gem 'font-awesome-rails'

# Git stuff
gem 'octokit', '~> 10.0'
gem 'faraday-http-cache'
gem 'faraday-retry'
gem 'github_webhook', '~> 1.4'

# Frontend: legacy stack — retired piecewise as views migrate to the
# Tailwind/Hotwire layout. Removed in Phase 4 Step 9.
gem 'bootstrap', '~> 4.5'
gem 'bootstrap_form'
gem 'haml', '~> 6.1.2'
gem 'haml-rails'
gem 'high_voltage'
gem 'jquery-rails'

# Frontend: modern stack — coexists with the legacy stack during the
# Phase 4 migration. The modern layout (`layouts/modern.html.haml`)
# opts in per-controller; the legacy `application.html.haml` keeps
# serving everything else.
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
