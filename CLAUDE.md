# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

MESATestHub is a Ruby on Rails application that manages test results for the MESA (Modules for Experiments in Stellar Astrophysics) stellar evolution code. It tracks test case execution across different commits, computers, and branches, integrating with GitHub for automated testing workflows.

## Development Commands

### Setup
- `bundle install` - Install Ruby gems
- `yarn install` - Install JavaScript dependencies (Node 18.x, Yarn 1.22.x required)
- `bundle exec rails db:setup` - Setup database (PostgreSQL for development/production, SQLite3 for testing)

### Running the Application
- `bundle exec rails server` - Start Rails development server
- `bundle exec puma` - Alternative server using Puma

### Testing
- `bundle exec rspec` - Run RSpec test suite
- `bundle exec cucumber` - Run Cucumber acceptance tests
- `bundle exec rails test:system` - Run system tests

### Database
- `bundle exec rails db:migrate` - Run database migrations
- `bundle exec rails db:seed` - Seed database with initial data
- `bundle exec rails db:reset` - Drop, create, migrate, and seed database

### Custom Rake Tasks
Available custom tasks in `lib/tasks/`:
- `morning_mailer:send` - Send morning summary emails
- `update_pulls:update` - Update pull request data
- `compute_delays` - Compute timing delays for test execution
- `cleanup_orphaned_commits` - Clean up orphaned commit records

## Architecture

### Core Models
- **Commit**: Represents Git commits from the MESA repository
- **TestCase**: Individual test cases that can be executed
- **TestInstance**: Execution results of a test case on a specific commit/computer
- **Computer**: Machines that execute test cases
- **Submission**: Batch submissions containing multiple test instances
- **Branch**: Git branches with associated commits
- **User**: System users who own computers

### Data Flow
1. GitHub webhooks trigger commit creation (`GithubWebhooksController`)
2. Test execution clients submit results via JSON API (`SubmissionsController`)
3. Results are stored as TestInstances with associated TestData/InlistData
4. Web interface displays results organized by commits and test cases

### Key Controllers
- `CommitsController`: Main interface showing test results by commit
- `TestCasesController`: Test case management and historical views
- `SubmissionsController`: API for receiving test results
- `ComputersController`: Computer registration and management

### GitHub Integration
- Uses Octokit gem for GitHub API access
- Caches API responses with faraday-http-cache
- Requires `GIT_TOKEN` environment variable for authentication
- Configured to work with `MESAHub/mesa` repository

### Database
- PostgreSQL for development and production
- SQLite3 for testing
- Extensive migration history in `db/migrate/`
- Uses Kaminari for pagination

### Frontend
- Bootstrap 4.5 for styling
- HAML templates for views
- CoffeeScript for JavaScript functionality
- Font Awesome icons

### Background Processing
- Morning mailer for daily summaries
- Puma worker killer for memory management
- Scout APM for production monitoring

## Environment Variables Required
- `GIT_TOKEN`: GitHub personal access token for API access
- `RAILS_MAX_THREADS`: Database connection pool size
- Database credentials (varies by environment)

## Testing Strategy
- RSpec for unit/integration tests with FactoryBot
- Cucumber for acceptance testing
- System tests with Capybara and Selenium
- Database cleaner for test isolation