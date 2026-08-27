# Artifacto

Drop a self-contained HTML (or Markdown) file, get a public link. No account, no
login. The link expires after 14 days.

**Live instance:** <https://3tpf0xkbxuc4pgalpbgmctdi.187.77.103.66.sslip.io/> —
a Coolify box on a throwaway hostname, running in single-origin mode. Treat it
as a staging deploy, not a place to put anything that matters.

Built for AI agents first: `skills/artifacto/SKILL.md` teaches Claude Code, Cursor
or anything else that can run `curl` to publish and then update the same link.
A running instance serves it at `/skill`, rewritten to point at that instance:

```bash
mkdir -p .claude/skills/artifacto
curl -fsS https://your-app.example.com/skill -o .claude/skills/artifacto/SKILL.md
```

`-f` there so a failed fetch does not write an error page into the skill file. Every
other call in the skill drops it, because the API explains its failures in the JSON
body and `-f` throws that body away.

## Why two domains

Artifacto hosts **arbitrary third-party HTML with JavaScript**, uploaded by anyone.
Isolation is the architecture. Set `CONTENT_HOST` and you get it:

| Zone | Serves | Notes |
|---|---|---|
| `APP_ORIGIN` (e.g. `https://artifacto.app`) | Landing page, wrapper page, API, admin | Sessions and cookies live here |
| `<slug>.CONTENT_HOST` (e.g. `<slug>.artifactousercontent.com`) | The artifact itself | Separate registrable domain, one origin per artifact, no cookies ever set |

The app itself is not host-constrained — it answers on whatever domain it is
deployed under, and `APP_ORIGIN` only pins the origin used in `frame-ancestors`
and in the URLs the API returns. `CONTENT_HOST` must be a **different registrable
domain**, not a subdomain of the app — that is what makes it impossible for an
artifact to receive an app cookie. Give it a boring, unbranded name: it will eventually be reported for
somebody's phishing page, and you do not want your brand in that blocklist.

Each artifact gets its own subdomain, so no two artifacts share `localStorage`,
`sessionStorage` or `IndexedDB`.

### Single-origin mode

Leave `CONTENT_HOST` unset and there is no second domain: artifacts are served
from `/raw/<slug>` on whatever host the request arrived on. One domain, no DNS
work, nothing to configure — and no origin boundary either.

To make up for it, `RawController` drops `allow-same-origin` from the sandbox in
this mode, which gives every artifact an opaque origin. That restores most of
what the second domain was doing: an artifact still cannot read the app's
storage, and no two artifacts share any. The costs are real, though:

- `localStorage`, `sessionStorage` and `IndexedDB` stop working inside artifacts.
- The app's own origin now serves attacker-supplied HTML, so anything reported
  for phishing is reported against your domain, not an unbranded one.
- The postMessage channel targets `*` instead of a named origin, because an
  opaque origin cannot name itself.

Fine for a staging box or a first deploy on a throwaway hostname. Set
`CONTENT_HOST` before it matters.

Artifacts are served under a policy that blocks `fetch`, form submission, top-level
navigation, popups, downloads and every external resource. An artifact cannot link
out at all — it is a closed page. `allow_network=true` opens `connect-src` for one
artifact and nothing else. See `RawController`.

Uploaded HTML is never sanitized — stripping `<script>` would break every
interactive artifact. Markdown is different: we render it, so it is sanitized and
gets a much stricter policy.

## Local development

```bash
bin/setup
bin/rails server -p 3000
```

Then open <http://localhost:3000>. With nothing configured this runs in
single-origin mode and artifacts appear at `http://localhost:3000/raw/<slug>`.

To develop against the two-zone layout instead, set `CONTENT_HOST` to a
`*.localhost` name — browsers resolve those to 127.0.0.1 with no `/etc/hosts`
editing:

```bash
CONTENT_HOST=usercontent.localhost APP_ORIGIN=http://localhost:3000 bin/rails server -p 3000
```

Artifacts then appear at `http://<slug>.usercontent.localhost:3000/`.

If port 3000 is taken, pass the port in both places so generated URLs match:

```bash
PORT=3100 bin/rails server -p 3100
```

Run the suite — it covers the isolation headers, so a regression there fails the build:

```bash
bin/rails test
```

## Configuration

There are no encrypted credentials. Every secret is an environment variable, and
the app reads nothing from disk that is not in git.

**Required in production**

| Variable | Example | Purpose |
|---|---|---|
| `SECRET_KEY_BASE` | `4f8a1c...` (128 hex chars, from `bin/rails secret`) | Signs cookies and the PIN tokens |
| `AR_ENCRYPTION_PRIMARY_KEY` | `9d3b7e...` (32+ chars, from `bin/rails secret`) | Encrypts `artifacts.creator_ip` at rest |
| `AR_ENCRYPTION_DETERMINISTIC_KEY` | `2a5f10...` (32+ chars, a *different* `bin/rails secret`) | Deterministic encryption key |
| `AR_ENCRYPTION_SALT` | `c710b4...` (32+ chars, a *third* `bin/rails secret`) | Key derivation salt |
| `DATABASE_URL` | `postgres://artifacto:s3cret@artifacto-db:5432/artifacto_production` | Merged over `config/database.yml`. Use the `DB_*` vars below instead if you prefer |
| `REDIS_URL` | `redis://artifacto-redis:6379/0` | Sidekiq queue and cron, and `Rails.cache` — which is where the API's rate-limit counters live, so this is not optional |

Boot fails loudly if any of the `AR_ENCRYPTION_*` keys are missing, so a
misconfigured deploy never quietly writes unencrypted IPs.

**Zones**

| Variable | Default | Example | Purpose |
|---|---|---|---|
| `CONTENT_HOST` | unset → single-origin mode | `artifactousercontent.com` | Parent domain for artifact subdomains. Must be a different registrable domain from the app |
| `APP_ORIGIN` | unset → taken from the request | `https://artifacto.app` | Origin used in `frame-ancestors` and the artifact's postMessage target. **Required when `CONTENT_HOST` is set**, ignored otherwise |

**Runtime**

| Variable | Default | Example | Purpose |
|---|---|---|---|
| `SIDEKIQ_IN_PUMA` | unset | `true` | Run Sidekiq inside Puma. Single-process Puma only — boot refuses it when `WEB_CONCURRENCY > 1` |
| `SIDEKIQ_CONCURRENCY` | `3` | `5` | Sidekiq threads. Counted into the Active Record pool |
| `RAILS_MAX_THREADS` | `3` | `5` | Puma threads. Also counted into the pool |
| `WEB_CONCURRENCY` | unset (single process) | `2` | Puma workers. Incompatible with `SIDEKIQ_IN_PUMA` |
| `PORT` | `3000` | `3000` | Puma's port. Thruster fronts it on 80 in the image |
| `RAILS_LOG_LEVEL` | `info` | `debug` | |
| `FORCE_SSL` | `true` | `false` | Redirects to https and marks cookies secure, assuming TLS terminates at the proxy in front. Set `false` only if the app is really served over http |

**Application**

| Variable | Default | Example | Purpose |
|---|---|---|---|
| `MAX_UPLOAD_BYTES` | `5242880` | `10485760` | Hard upload limit |
| `DEFAULT_TTL_DAYS` | `14` | `14` | Default lifetime, 1–30 allowed |
| `ARTIFACT_CACHE_SECONDS` | `300` | `0` | How long a served artifact stays fresh in browsers and at the edge. A `PUT` keeps the URL, so this is also how long a reader can keep seeing the previous version after an update. `0` forces revalidation on every view, answered by the ETag with a 304 |
| `IP_HASH_SECRET` | `dev-secret` | `e91c44...` (from `bin/rails secret`) | HMAC key for `creator_ip_hash`. Rotating it orphans existing bans |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | `admin@example.com` / `password` in dev | `igor@example.com` / `a-long-random-string` | The admin `bin/rails db:seed` creates. Seeding sets the password every run, so it also recovers a lost one. In production an unset `ADMIN_PASSWORD` generates a random one and prints it |
| `CF_ZONE_ID` / `CF_API_TOKEN` | — | `0a1b2c...` / `v1.0-...` | Purge the CDN on update. The job no-ops without them, and in single-origin mode |

**Database, if you are not using `DATABASE_URL`**

| Variable | Default | Example |
|---|---|---|
| `DB_HOST` | `localhost` | `artifacto-db` |
| `DB_PORT` | `5432` | `5432` |
| `DB_USER` | `artifacto` | `artifacto` |
| `ARTIFACTO_DATABASE_PASSWORD` | — | `a-long-random-string` |

## Deploy

Any Docker host works — the image reads everything from env vars, so there is no
`master.key` to ship. The smallest deploy that runs is single-origin mode:
`SECRET_KEY_BASE`, the three `AR_ENCRYPTION_*` keys, `DATABASE_URL`, `REDIS_URL`
and `SIDEKIQ_IN_PUMA=true`. No hostname is configured anywhere, so the app
answers on whatever domain the platform gives it. Read **Single-origin mode**
above before leaving it that way.

Generate the five secrets, one run each:

```bash
bin/rails secret
```

`config/deploy.yml` still describes a Kamal deploy onto one small box: Postgres
and Valkey run as accessories next to the app, and Sidekiq runs inside Puma.

**Give the app an `https://` domain before you trust any form on it.** In Coolify
that is the scheme in the Domains field: with `http://` it only builds a port-80
router, never requests a certificate, and Traefik answers 443 with
`no available server`. Meanwhile `FORCE_SSL` defaults to on, which pairs
`assume_ssl` with `force_ssl`, so Rails believes every request already arrived
over TLS and marks the session cookie `Secure`. A browser discards a `Secure`
cookie from an `http://` origin, which empties the session and fails CSRF
verification — every form returns 422 while the pages themselves look fine.

So: use `https://` and leave `FORCE_SSL` alone. Set `FORCE_SSL=false` only for a
deploy that genuinely has no TLS in front of it, and expect no secure cookies.

**Networking.** kamal-proxy takes every host that reaches it, because it has to
answer for the app's own hostname and for every artifact subdomain. Let's Encrypt cannot issue
that wildcard over HTTP-01, so TLS terminates at Cloudflare and the last hop runs
through a Cloudflare Tunnel (`tunnel` accessory). The box needs no certificate and
no inbound port. Point both public hostnames at `http://kamal-proxy:80` in the
tunnel's config.

### Cloudflare

Both zones, free plan.

**App zone**
- WAF managed rules on; rate limiting rule on `POST /api/v1/*`.
- **Turn Bot Fight Mode off.** It blocks `curl`, which breaks the skill — this is
  the most common cause of mysterious 403s here.

**Content zone**
- Wildcard `*` record, proxied. Universal SSL covers one level of subdomain.
- Cache rule: cacheable, edge TTL respects origin.
- **Configuration rule for the whole zone: Rocket Loader OFF, Auto Minify OFF,
  Email Obfuscation OFF, Mirage OFF.** These inject Cloudflare's own JavaScript
  into the HTML, which corrupts artifacts and adds a script the policy does not
  expect. Not optional.
- Consider submitting the zone to the [Public Suffix List](https://github.com/publicsuffix/list).
  Once accepted, browsers refuse zone-wide cookies there, closing the last way one
  artifact could interfere with another.

After deploying, confirm Cloudflare did not rewrite a body:

```bash
curl -s https://<slug>.<content-host>/ | gunzip | sha256sum
```

Compare against `Artifact#served_html` for that slug. A mismatch means Rocket
Loader is on.

## Comments

Readers annotate an artifact in place: click **Comment** in the wrapper bar, click a
spot in the page, type. A pin appears there and stacks into a thread on repeat
visits. **All comments** in the same bar opens a side panel listing every one of
them — including the ones whose anchor no longer resolves — and deletes any of
them against the artifact's edit token, which the panel asks for once and keeps
in `localStorage`. No account — whoever holds the link can comment.

The name box beside the comment body is optional and unverified: it is stored as
`comments.author`, returned by the API, and remembered in `localStorage` so the
same reader does not retype it on the next artifact. Nothing checks it, so it
labels a thread and nothing more.

The wrapper page and the artifact never share a document, so the whole feature
runs over the `postMessage` channel opened by `app/javascript/artifact_agent.js`:

| Direction | Message | Payload |
|---|---|---|
| artifact → app | `artifacto:ready` | — |
| artifact → app | `artifacto:anchor` | the clicked element's selector, a text quote, click coordinates |
| artifact → app | `artifacto:positions` | where each anchor currently sits, re-sent on scroll and resize |
| app → artifact | `artifacto:mode` | comment mode on/off |
| app → artifact | `artifacto:anchors` | the selectors and quotes to resolve |

**Comment bodies never cross into the artifact.** The frame is asked where things
are and nothing else; every body is fetched, stored and rendered on the app origin,
with `textContent`, so reader text can never become markup in either zone.

**Re-anchoring.** A `PUT` replaces the artifact body, so the stored `nth-of-type`
chain usually stops resolving the moment the agent updates the page. That is why
the quote is stored next to it. The quote also decides on the *happy* path: a
selector that still resolves is not proof it resolves to the same thing — insert
one paragraph and `body > p:nth-of-type(2)` points at different text — so the
element it finds only counts if it still contains the quote. Otherwise the frame
searches for the deepest element that does — over rendered text only, since
`textContent` includes the source of any `<script>`, and an artifact that builds
its own page contains the very words the reader quoted out of it. Pins say which happened: blue
resolved and still says the same thing, violet re-anchored on the quote, red
could not be placed at all and parks in the top-left corner rather than
disappearing. Nothing acknowledges an anchors message, so the pins are the receipt: the page
asks again while any of them is unplaced, and a frame that still says nothing
gets the red treatment. That covers both a hook older than the current protocol
and an artifact declining to answer about criticism of itself.

**A PIN covers the comments too.** A stored quote is up to 200 characters lifted
straight out of the page, so the comment endpoints take the same short-lived
signed token the content zone does — minted on the wrapper page once the PIN has
been entered, and passed as `?t=`. The edit token outranks it: whoever published
the artifact set the PIN, so `Authorization: Bearer` reads and deletes without
one.

**Changing the hook is a two-part change.** The script is spliced into the body at
write time, so a stored row keeps whatever version it was written with. Bumping
`AgentInjector::VERSION` therefore has to come with a backfill —
`Artifact#refresh_agent_hook!` over existing rows, the way
`db/migrate/*_refresh_agent_hook.rb` does. Skip it and old artifacts keep a hook
the overlay cannot talk to, and a Markdown artifact is served a `csp_hash` that
does not match its own inline script, which blocks the script outright.

### For the agent that wrote the artifact

This is the loop the product exists for: publish, get read, get told what is wrong,
fix it, `PUT` the same URL.

```bash
curl -sS "$BASE/api/v1/artifacts/$SLUG/comments"
curl -sS -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE/api/v1/artifacts/$SLUG/comments/$ID"
```

Reading needs nothing; deleting needs the edit token. `skills/artifacto/SKILL.md`
documents both.

### Admin area

`/admin` is behind Devise now, not HTTP Basic. Users have one of two roles,
`user` (the default) and `admin`, and only `admin` gets past
`Admin::BaseController`. Everyone else is redirected to `/`.

There is no public signup and no password reset: accounts exist only to gate
`/admin`, so both would be unauthenticated, unrate-limited endpoints buying
nothing. `/users/sign_in` is the only Devise route.

- `bin/rails db:seed` creates `ADMIN_EMAIL`, or resets its password if the
  address already has an account, and makes it an admin. `bin/docker-entrypoint`
  runs it as part of `db:prepare` the first time the database is created.
- Later accounts come from the console: `User.create!(email:, password:)`, then
  promote from `/admin/users` if they need it.
- `/admin` is a dashboard: artifact, user, engagement, moderation and storage counters,
  plus a 14-day bar of new artifacts.
- `/admin/users` lists every account with its artifact count and flips roles.
  An admin cannot demote themselves, so the last one out cannot lock the door.
- `/admin/artifacts` and `/admin/comments` are unchanged apart from the new auth.

`artifacts.user_id` is wired to `users` but nothing sets it yet — uploads come in
over the token API, so **Have published** and **Top creators** stay at zero until
creation learns to attribute.

### Moderation

Comments are the first user text served from the app's own origin, and
`blocked_hashes` does not cover them — that list is about artifact bytes. What
holds the line instead:

- 20 comments per IP per hour (Rails' `rate_limit`, so Redis-backed and surviving deploys)
  and 500 per artifact.
- 2 000 characters, stored as text, rendered as text.
- `author_ip_hash` on every row, the same HMAC used for artifacts.
- A PIN-locked artifact needs its unlock token before comments can be read or written.
- `/admin/comments` lists the most recent 200 and deletes any of them.

**Comments and single-origin mode are a bad pair.** In single-origin mode your app
domain already serves attacker-supplied HTML; a commenting surface on the same
domain adds attacker-supplied *text* under your brand, with a form that invites it.
Set `CONTENT_HOST` before turning readers loose on a public instance.

## Abuse

Upload is open to anyone with no key, so assume the service will be found.

**What the serving policy already makes impossible.** A credential-harvesting form
cannot submit (`form-action 'none'`, which covers `mailto:` too). Nothing can be
exfiltrated (`connect-src 'none'`). No remote payload can be pulled in
(`default-src 'none'`). The viewer cannot be redirected or handed a file: the
sandbox allows neither top-level navigation, nor popups, nor downloads. The usual
phishing and malware pages simply do not function here.

**What is left, and what answers it.**

| Remaining vector | Mitigation |
|---|---|
| Illegal or abusive images, embedded as base64 | Report button → `/admin` → block, which adds the file hash *and* every embedded image hash to `blocked_hashes`. Re-uploading the same bytes then fails with 451, in any wrapper |
| Text-only scams, hate, doxxing | Report and manual review. No automated classifier yet |
| Abusive comments | Rate limited per IP, capped per artifact, deleted from `/admin/comments`. See **Comments** above |
| Anything at all | 14-day TTL bounds exposure; `noindex` keeps it out of search |

`blocked_hashes` is exact SHA-256, so a single flipped byte evades it. Perceptual
hashing (PhotoDNA/NCMEC for images) is the upgrade path, and is the only real
answer for CSAM. Note that Cloudflare's CSAM scanner cannot help here: our images
are inlined as `data:` URIs, not separate requests, so nothing sees them but us.

If abuse outgrows manual review, the two levers, in order of effect: require an API
key on upload (`REQUIRE_API_KEY` is reserved for it), and classify text and images
at upload in a background job.

**Uploader identity.** `creator_ip_hash` is an HMAC used for banning. The raw IP is
stored separately, encrypted with Active Record Encryption, and scrubbed 30 days
after upload (`Artifact::IP_RETENTION`) so a lawful request about a specific
artifact can be answered. Say so in your privacy policy.

**Before going public**, none of which is code: publish terms and an acceptable-use
policy, an `abuse@` address and a takedown page with a stated response time. A
server in Germany puts you under the EU DSA, which requires a notice-and-action
mechanism and a point of contact. Hetzner suspends machines on abuse complaints
faster than you will read the mail, so response time is an operational requirement.

## Backups

There are none, deliberately. Artifacts live at most 30 days and the agent that
produced one can produce it again.

If that stops being true — accounts land in phase 3, and a dashboard people log
into is a thing worth being able to restore — object storage is where the
Postgres dumps would go: <https://secure.backblaze.com/b2_buckets.htm>.

## Not built yet

- Accounts and a dashboard (`artifacts.user_id` is already there). Until then the
  edit token is shown exactly once and cannot be recovered: lose it and the link
  is permanent and unchangeable until it expires.
- Owner controls on the wrapper page. Extending expiry and deleting are API-only,
  so anyone holding the edit token has to reach for `curl`.
- Threaded replies. Comments sharing an anchor render as one thread; there is no
  parent/child relationship behind that.
- Version history and rollback.
