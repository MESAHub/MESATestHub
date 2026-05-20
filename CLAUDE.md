# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project orientation

MESATestHub is a Ruby on Rails app that tracks test results for the MESA
(Modules for Experiments in Stellar Astrophysics) stellar evolution code. Test
clients submit results via a JSON API; the web interface shows results
organized by commits, branches, computers, and test cases. GitHub webhooks
drive commit ingestion from `MESAHub/mesa`.

- **Production**: Railway (`mesatesthub-production.up.railway.app`),
  Postgres service. Heroku still runs in parallel on `testhub.mesastar.org`
  during the cutover; that domain is expected to repoint at Railway.
- **Solo maintainer**, low-but-important traffic (the MESA dev community).
  Downtime of a few days is tolerable; data integrity is not negotiable.

## Where context lives

Before doing non-trivial work, read the appropriate doc:

- **[`docs/roadmap.md`](docs/roadmap.md)** — sequenced plan for ongoing
  modernization work (test foundation → Rails 7 upgrade → perf → frontend).
  Active phase and branch are noted there. **Check this first** before
  proposing structural changes; the plan may already cover them.
- **[`docs/rails-upgrade.md`](docs/rails-upgrade.md)** — detailed Rails
  6.1 → 7.x upgrade plan, remaining Dependabot advisories, gem
  compatibility analysis, real-world exposure assessment.

When changes invalidate the plan, update the relevant doc in the same commit
that makes the change.

## Reality checks (things the codebase *looks* like but isn't)

- The Rails 5.1 `config.load_defaults 5.1` in `config/application.rb` is real.
  The app runs on Rails 6.1 code but with Rails 5.1 default behaviors. Both
  `new_framework_defaults_5_2.rb` and `new_framework_defaults_6_0.rb` exist
  with every option commented out. This will be flipped phase-by-phase
  during the Rails upgrade.
- **There is effectively no test suite.** Most files under `spec/` are
  generator stubs (`pending "add some examples..."`). Only
  `spec/models/test_case_spec.rb` has real content. The active branch
  `tests/api-foundation` is building the first real coverage.
- **No Cucumber.** The old Cucumber suite has been moved to
  `features.deprecated/` and `spec/features.deprecated/`. RSpec request
  specs replace it for new work. Do not add `.feature` files.
- **No user-facing Active Storage**. The default `:local` service is
  scaffolding only. The high-severity Active Storage CVEs are unreachable
  in this codebase.
- **The Sprockets asset pipeline does not have committed compiled assets**
  any more. `public/assets/` is gitignored. Sprockets compiles fresh on
  every Railway deploy.

## Development commands

### Setup
- `bundle install` — Ruby gems
- `yarn install` — JS deps (Node 18.x, Yarn 1.22.x)
- `bundle exec rails db:setup` — Postgres in all environments

### Run
- `bundle exec rails server` — development server
- Local DB is `development` (Postgres on `localhost:5432`). Most recent
  prod snapshot has been restored to it.

### Test
- `bundle exec rspec` — full suite. **Aim for green on every commit to
  feature branches.**
- `bundle exec rspec spec/requests/auth_spec.rb` — single file.
- CI runs the same command on push + PR via `.github/workflows/test.yml`.

### Database
- `bundle exec rails db:migrate`
- `bundle exec rails db:reset` — drop, create, migrate, seed
- To re-pull prod data:
  ```
  heroku pg:backups:capture && heroku pg:backups:download
  pg_restore --no-acl --no-owner --clean --if-exists -d development latest.dump
  ```
  (Local Postgres is via Postgres.app at
  `/Applications/Postgres.app/Contents/Versions/17/bin/`.)

### Custom Rake tasks (in `lib/tasks/`)
- `morning_mailer:send` — daily summary emails
- `update_pulls:update` — GitHub PR data
- `compute_delays`
- `cleanup_orphaned_commits`

## Architecture

### Core models
- **Commit** — Git commits from the MESA repo
- **Branch**, **BranchMembership** — branches and the join table
- **TestCase** — a single test that can run
- **TestCaseCommit** — aggregate test-case state per commit
- **TestInstance** — one execution of a test case on a specific commit + computer
- **TestDatum**, **InlistDatum**, **InstanceInlist** — per-instance metric data
- **Computer** — machines that run tests
- **Submission** — a batch of test instances from a computer
- **User** — operator of one or more computers; some are admins

### Data flow
1. GitHub webhooks (`GithubWebhooksController`) ingest commits.
2. Test clients POST results to `SubmissionsController#create` (JSON).
3. Web UI (`CommitsController`, `TestCasesController`,
   `TestCaseCommitsController`) reads from the DB.

### GitHub integration
- `octokit` for the API, `faraday-http-cache` for caching, `faraday-retry`
  for transient-error resilience.
- `GIT_TOKEN` env var = personal access token.
- Hard-coded to `MESAHub/mesa`.

## Conventions

- **Branches**: kebab-case, prefix by purpose: `tests/`, `rails-upgrade`,
  `perf-`, `frontend-`, `fix-`, `feature-`.
- **Commits**: short imperative subject, present-tense verb. Match style of
  existing `git log` (e.g., "Restrict most pages to logged-in users to
  reduce traffic"). Body when the *why* needs explanation.
- **No Co-Authored-By trailers** in commits unless explicitly requested.
- **Never commit precompiled assets** (`public/assets/`). Sprockets does this
  at deploy time.
- **Never commit DB dumps**. They get UUID-style names and slip through;
  `.dump` is gitignored.

## Environment variables

Production (Railway service):
- `RAILS_ENV`, `RACK_ENV` = `production`
- `RAILS_LOG_TO_STDOUT`, `RAILS_SERVE_STATIC_FILES` = `enabled`
- `SECRET_KEY_BASE` — random, regenerate with `bundle exec rails secret`
- `DATABASE_URL` — reference to Railway Postgres service
- `GIT_TOKEN`, `GIT_USERNAME`, `GITHUB_WEBHOOK_SECRET` — GitHub API + webhook
- `OWNER_EMAIL`, `MAILGUN_SMTP_*` — outbound mail (Mailgun via Heroku
  add-on, *to be migrated*)
- `DISABLE_SPRING` = `1` — Spring binstubs are present but must not run in
  production
- `MISE_RUBY_COMPILE` = `false` (optional) — skip from-source Ruby build
  on Railway

## Quick gotchas

- Spring is in the dev Gemfile and writes binstubs. Production runs Spring
  by accident if invoked through `bin/rails` without `DISABLE_SPRING`.
- The mailer config uses Mailgun SMTP env vars but the underlying provider
  is incidental. Switching email providers is a 4-env-var change, no code.
- `barista` gem is listed in Gemfile but unused — leave it alone for now
  (slated for removal during frontend modernization phase).
- `app/mailers/morning_mailer.rb` has several hardcoded
  `https://testhub.mesastar.org/...` URLs that build email body links. They
  need updating before the custom domain shifts or those emails will point
  at the old Heroku app.

## When in doubt

- Pull `docs/roadmap.md` to see what phase is active and whether the work
  in question belongs to that phase or a different one.
- Don't write tests for code that isn't on the active branch's critical
  path. The test foundation is intentionally small.
- Don't mix the upgrade with frontend changes. One axis of change per
  branch.
