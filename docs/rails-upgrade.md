# Rails upgrade tracker

This document captures the current state of the Rails dependency, the remaining
Dependabot advisories that can only be resolved by a Rails major upgrade, and a
proposed path forward — informed by an actual audit of the codebase rather than
generic Rails-upgrade lore.

## Current state

- **Rails 6.1.7.10** — the final 6.1.x release.
- Rails 6.1 reached **end of security support in October 2024**. No further CVE
  backports are coming.
- All non-Rails gems with known advisories have been patched on master.
- **`config.load_defaults 5.1`** in `config/application.rb` — the app runs on
  Rails 6.1 code but uses Rails 5.1 default behaviors. See "Stale framework
  defaults" below.
- **No meaningful test suite.** `spec/` directories exist but coverage is
  effectively zero. This is the single biggest amplifier on upgrade effort:
  every phase must be verified by hand against production behavior.

## Remaining Dependabot advisories

These all target Rails internals and have no 6.1.x backport. They will keep
appearing in Dependabot until the app is on Rails ≥ 7.0.8.7 (for the actionpack
CSP advisory) and ideally Rails ≥ 7.2.3.1 (for the rest).

| GHSA | Package | Severity | Summary |
|---|---|---|---|
| GHSA-r4mg-4433-c7g3 | activestorage | critical | Active Storage allowed potentially unsafe transformation methods |
| GHSA-9xrj-h377-fr87 | activestorage | high    | Possible path traversal in DiskService |
| GHSA-73f9-jhhh-hr5m | activestorage | medium  | Possible glob injection in DiskService |
| GHSA-p9fm-f462-ggrg | activestorage | low     | DoS via multi-range requests in proxy mode |
| GHSA-r46p-8f7g-vvvg | activestorage | medium  | DoS via Range requests in proxy mode |
| GHSA-qcfx-2mfw-w4cg | activestorage | medium  | Content-type bypass via metadata in direct uploads |
| GHSA-2j26-frm8-cmj9 | activesupport | medium  | DoS in number helpers |
| GHSA-cg4j-q9v8-6v38 | activesupport | medium  | ReDoS in `number_to_delimited` |
| GHSA-89vf-4333-qx8v | activesupport | medium  | XSS in `SafeBuffer#%` |
| GHSA-76r7-hhxj-r776 | activerecord  | medium  | ANSI escape injection in logging |
| GHSA-vfm5-rmrh-j26v | actionpack    | low     | CSP bypass in Action Dispatch |
| GHSA-v55j-83pf-r9cq | actionview    | low     | XSS in tag helpers |

### Real-world exposure (this app specifically)

For an internal MESA-developer-facing tool sitting behind authentication, with
no user-uploaded files, several of these advisories are effectively unreachable:

- **All Active Storage advisories**: this app does not accept user uploads.
  The default `config.active_storage.service = :local` is scaffolding only — no
  controller exposes upload endpoints, so `DiskService` is never exercised
  against attacker-controlled input.
- **`number_to_delimited` ReDoS / `SafeBuffer#%` XSS**: only reachable if
  user-supplied input is passed directly to these helpers. Worth a code audit
  if/when these are reached on untrusted data; currently low risk.
- **Active Record ANSI escape injection**: only matters if log output is
  rendered into a terminal that interprets escape codes from attacker-controlled
  fields. Railway's log UI sanitizes — minimal exposure.

The critical-rated Active Storage advisory has the loudest banner but is the
clearest example of "vulnerable in theory, unreachable in this codebase." It
should still be resolved by upgrading, but not because there's an active
exploitation risk.

## Code-level findings from the audit

### Mandatory code changes for Rails 7

Only two:

- `app/models/test_case.rb:371` — `update_attributes` → `update`
- `app/models/test_instance.rb:607` — `update_attributes` → `update`

`update_attributes` was deprecated in Rails 6.1 (logs a warning) and **removed
in Rails 7.0**. Without this fix, those code paths will raise
`NoMethodError`.

### Stale framework defaults

`config/application.rb` declares `config.load_defaults 5.1`. Both
`new_framework_defaults_5_2.rb` and `new_framework_defaults_6_0.rb` exist
with every option commented out — meaning none of the post-5.1 default
behaviors are active.

Latent behaviors that will switch on during the upgrade:

| Default | Introduced | User-visible risk |
|---|---|---|
| AES-256-GCM cookie encryption | 5.2 | **Forces session/cookie re-encryption — all users logged out once on first deploy.** |
| `form_with` generates id attributes | 5.2 | CSS/JS targeting form internals may break in unexpected ways |
| SHA-1 instead of MD5 for ETag digests | 5.2 | Negligible — all caches invalidate once |
| Cookie purpose/expiry metadata | 6.0 | Forwards-incompatible with older Rails — fine going forward |
| `ActionMailer::MailDeliveryJob` | 6.0 | Only matters if mail is sent via background jobs (this app uses synchronous delivery) |
| `ActionDispatch::Response#content_type` returns media type only | 6.0 | Code reading `response.content_type` may need updating |

None of these require code changes per se; they need to be enabled and the
resulting behavior verified.

### Codebase scale

- ~6,400 lines across `app/models`, `app/controllers`, `app/mailers`
- Two large models: `commit.rb` (785), `test_instance.rb` (833)
- Largest mailer: `morning_mailer.rb` (676) — already in scope for separate
  email-provider migration
- 13 CoffeeScript files in `app/assets/javascripts/`
- 14+ SCSS files in `app/assets/stylesheets/`

### Modern patterns already in use

The codebase uses `before_action`, `respond_to`, `render json:`,
`protect_from_forgery`, strong parameters, and idiomatic associations. No
legacy patterns surfaced by grep: no `before_filter`, no `update_attribute`
chains, no `render text:`, no `alias_method_chain`. The Rails 7 migration is
mostly mechanical from a code standpoint.

### Things that survive unchanged

| Component | Rails 7 status |
|---|---|
| Sprockets asset pipeline | Still works — Rails 7 keeps it as a working option |
| CoffeeScript (13 files) | `coffee-rails 4.2` + Sprockets continues working |
| Turbolinks 5 | Gem still works; migration to turbo-rails is optional |
| SCSS via sassc-rails | Deprecated but functional |
| Homegrown bcrypt + session authentication | No Rails-version sensitivity |
| Active Storage (no user flow) | Configuration is just scaffolding |
| ActionCable | Boilerplate only; could be deleted |

### Gems flagged for removal or attention

- **`barista`** (Gemfile only, no code references). CoffeeScript pre-processor,
  redundant with Sprockets + coffee-rails. Last release 2017. Delete it as part
  of the upgrade prep.
- **`uglifier`**. JS minifier, works on Rails 7 but deprecated. Modern Rails
  uses `terser`. Not blocking; address if/when convenient.
- **`sassc-rails`** (transitively). Works on Rails 7 but underlying `sassc` is
  deprecated. Replace with `dartsass-sprockets` only if a CSS regression forces
  it.

## Upgrade plan

A direct jump from 6.1 → 7.2 is not recommended. Sequential
one-minor-at-a-time jumps keep regressions bisectable and contain blast radius.
Because there is no test suite, each phase must be verified by hand against the
running app.

### Phase 0 — preparation
- Delete the `barista` gem.
- Fix the two `update_attributes` calls (do this *before* the Rails 7 jump so
  they don't compound with framework-defaults churn).
- Establish a manual smoke-test checklist: login, view commits, view test case,
  submit a result via API, trigger a webhook, view computer listings,
  authenticated/unauthenticated browsing patterns. Run it as a baseline on
  current production.

### Phase 1 — flip `load_defaults` to 5.2
- Bump `config.load_defaults 5.1` → `5.2` in `config/application.rb`.
- Delete `new_framework_defaults_5_2.rb` (no longer needed).
- Deploy to Railway, run smoke checklist, watch logs for deprecation noise.
- Expect: all users logged out once due to cookie encryption change.

### Phase 2 — flip to 6.0
- Bump `config.load_defaults 5.2` → `6.0`.
- Delete `new_framework_defaults_6_0.rb`.
- Smoke test again.

### Phase 3 — flip to 6.1
- Bump to `6.1`. A new `new_framework_defaults_6_1.rb` would normally be
  generated by `bin/rails app:update`, but defaults are minor and most can be
  accepted as-is.
- Smoke test.

### Phase 4 — bump Rails to 7.0
- `gem 'rails', '~> 7.0'` in Gemfile.
- `bin/rails app:update` — review each prompted change.
- Resolve gem version conflicts (most should be transparent).
- Bump `load_defaults` to `7.0`.
- Smoke test, deploy.

### Phase 5 — bump Rails to 7.1
- `gem 'rails', '~> 7.1'`.
- `bin/rails app:update`.
- Smoke test, deploy.

### Phase 6 — bump Rails to 7.2
- `gem 'rails', '~> 7.2'`.
- `bin/rails app:update`.
- Smoke test, deploy.
- All remaining Dependabot advisories close.

### Estimated effort

| Phase | With a real test suite | Without (current state) |
|---|---|---|
| 0   | 2–4 hrs   | 4–6 hrs (longer baseline smoke list) |
| 1–3 | 6–12 hrs  | 12–20 hrs (manual verification at each flip) |
| 4   | 4–8 hrs   | 8–12 hrs |
| 5   | 2–4 hrs   | 4–6 hrs |
| 6   | 2–4 hrs   | 4–6 hrs |
| **Total** | **~20–30 hrs** | **~35–50 hrs / ~5–7 days** |

The absence of a test suite roughly doubles the effort because manual
verification has to substitute for automated regression detection.

## Optional safety-net work before starting

Investing 1–2 days in characterization tests **before** the upgrade pays for
itself many times over. Targets that would catch the most regressions:

- **Request specs** for the auth flow, the major show pages
  (`commits#show`, `test_cases#show`, `test_case_commits#show`), and the
  submission API. Even basic "responds 200 with valid params" coverage is huge.
- **Model specs** for the two large models (`commit.rb`, `test_instance.rb`),
  covering the methods that compute statistics and aggregations.
- **A single webhook smoke test** that exercises `GithubWebhooksController`
  against a captured payload.

A reasonable target: ~15–20 spec files covering the most-loaded controllers
and the messiest model methods. That's a week's worth of test writing that
saves perhaps two weeks of manual upgrade verification, and leaves you with a
permanent regression safety net.

## Until the upgrade lands

In the Dependabot UI, the remaining advisories can be **dismissed as "Risk
tolerated"** with a note pointing to this document. That stops the banner from
shouting without falsely claiming the advisories were patched. Re-evaluate
quarterly or whenever the upgrade ships.

## Related work

- `Gemfile` / `Gemfile.lock` — current pinned versions live here.
- `.github/dependabot.yml` — verify scheduling/grouping if Dependabot becomes
  noisy after the upgrade lands.
- `config/initializers/new_framework_defaults_5_2.rb` — to be deleted in Phase 1.
- `config/initializers/new_framework_defaults_6_0.rb` — to be deleted in Phase 2.
