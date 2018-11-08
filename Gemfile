source 'https://rubygems.org'
git_source(:github) do |repo_name|
  repo_name = "#{repo_name}/#{repo_name}" unless repo_name.include?("/")
  "https://github.com/#{repo_name}.git"
end
ruby '~> 2.4'
gem 'sinatra', '~> 2.0.2'
gem 'rails', '~> 5.1.4'
gem 'puma', '~> 3.7'
gem 'sass-rails', '~> 5.0'
gem 'uglifier', '>= 1.3.0'
gem 'coffee-rails', '~> 4.2'
gem 'turbolinks', '~> 5'
gem 'jbuilder', '~> 2.5'
gem 'pg'
gem 'bcrypt', '~> 3.1.7'
gem 'sendgrid-ruby'
gem 'kaminari'
gem 'loofah', '~> 2.2.3'
gem 'rails-html-sanitizer', '~> 1.0.4'
gem 'rails_12factor', group: :production
gem 'scout_apm', group: :production
# gem 'sprockets', '~> 4.0.0.beta4'
gem 'mini_racer', :require => nil
gem 'rubyzip', '~>1.2.2'
gem 'barista'
group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
  gem 'guard-bundler'
  gem 'guard-rails'
  gem 'guard-rspec'
  gem 'guard-cucumber'
  gem 'cucumber-rails', require: false
  gem 'cucumber-rails-training-wheels'  
  gem 'capybara', '~> 2.13'
  gem 'selenium-webdriver'
end
group :development do
  gem 'web-console', '>= 3.3.0'
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
end
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]
gem 'bootstrap', '~> 4.1.2'
gem 'bootstrap_form'
gem 'haml', '~> 5.0.4'
gem 'haml-rails'
gem 'high_voltage'
gem 'jquery-rails'
group :development do
  gem 'better_errors'
  gem 'html2haml'
  gem 'rails_layout'
  gem 'rb-fchange', :require=>false
  gem 'rb-fsevent', :require=>false
  gem 'rb-inotify', :require=>false
  gem 'spring-commands-rspec'
end
group :development, :test do
  gem 'factory_girl_rails'
  gem 'faker'
  gem 'rspec-rails'
  gem 'sqlite3'
end
# group :production do
#   gem 'pg'
# end
group :test do
  gem 'database_cleaner'
  gem 'launchy'
end
