# Per-computer API keys

**Status:** testhub side implemented on `feature-computer-api-keys`
(Oct 2026). The `mesa_test` side ships with the claims-aware client
(dispatcher Phase D, [`dispatcher-and-claims.md`](dispatcher-and-claims.md)).

## Why

`mesa_test` used to authenticate every request with the user's email
and password:

- The password sat in plain text in `~/.mesa_test/config.yml`, often
  on shared cluster filesystems. It's also the website login, admin
  rights included.
- It was bcrypt-verified on every request, and a run sends hundreds
  of one-test submissions (plus, with claims, hundreds of claims).
- There was no way to cut off one machine without changing the
  password everywhere.

A key belongs to one computer, identifies it by itself, can be
replaced or revoked from that computer's page, and can't log into the
website.

## Passwords still work

Nothing forces anyone onto keys. Every endpoint that accepted email +
password still does, unchanged. A request that sends **no** key goes
down the old path exactly as before.

A request that **does** send a key is judged on the key alone:

| Key sent | Result |
|---|---|
| none | legacy email + password (or browser session), unchanged |
| valid | authenticated as the key's computer and its owner |
| valid, but `submitter[:computer]` names another computer | 422, nothing written |
| unknown / revoked | **401 `{"error":"Invalid API key."}`**, even if a valid password is also present |

The last row is deliberate. Falling back to the password would hide a
revoked key, and revoking a key should actually stop that machine.

## Wire format

```
Authorization: Bearer mth_<43 url-safe base64 chars>
```

Accepted on:

| Endpoint | Notes |
|---|---|
| `POST /submissions/create.json` | `submitter:` block optional; send `submitter: { platform_version: … }` if you have it |
| `GET /submissions/request_commit.json` | legacy dispatcher |
| `POST /api/v1/claims`, `POST /api/v1/dispatch` | `submitter:` block optional |
| `GET /test_instances/search.json`, `search_count.json` | key acts as the computer's owner |
| `POST /check_computer.json` | returns `{ valid:, computer:, message: }`; pass `computer_name` to also check the key belongs to it |

## Storage

Columns on `computers`:

- `api_key_digest`: SHA-256 hex of the key, with a unique index.
  Lookup is one equality match. The key is 32 random bytes, so a fast
  hash is safe; bcrypt would only slow down the hot path.
- `api_key_prefix`: the first 10 characters (`mth_` + 6). The
  computer page shows it so users can tell which key is active.
- `api_key_created_at`.
- `api_key_last_used_at`: refreshed at most every 5 minutes
  (`Computer::API_KEY_TOUCH_INTERVAL`), so a run doesn't write it on
  every submission.

One key per computer. Generating a new key replaces the old one.

## UI

Only the computer's owner or an admin sees the API key card on the
computer page:

- **Generate key** / **Replace key** posts to `computers#create_api_key`.
  That action renders the plaintext once, on its own page, with a copy
  button.
- The form opts out of Turbo, so a 200 render after the POST is fine
  and the key never passes through the flash/session cookie. That also
  means Replace confirms with a plain `onsubmit` confirm rather than
  `turbo_confirm`.
- Reloading that page redirects back to the computer page; the key is
  gone for good.
- **Revoke** is a `button_to … method: :delete`.

## Rate limiting

- `safelist('allow valid API keys')` in
  [`config/initializers/rack_attack.rb`](../config/initializers/rack_attack.rb)
  exempts requests with a valid key from the per-IP throttles, the
  same as a logged-in browser session. An unknown key gets no
  exemption.
- `SUBMISSION_PATH` now covers `/api/v1/` as well as `/submissions`.
  Claims are per test, so a password-authenticated claims client would
  otherwise hit the 100-requests-per-5-minutes IP throttle mid-run.
- The test environment's cache is `:null_store`, where throttles never
  count anything. The rack-attack spec swaps in a `MemoryStore` so its
  "not throttled" assertions mean something.

## Later

- **Logs.** The same key should authorize log uploads once logs move
  into object storage (roadmap backlog). That removes the separately
  issued `logs_token`.
- **Retiring passwords.** Once a key-capable `mesa_test` has been out
  a while, consider deprecating password auth on the API: warn in the
  response first, refuse later. Not decided; passwords stay for now.
