# Artifacto

Drop a self-contained HTML (or Markdown) file, get a public link. No account, no
login. The link expires after 14 days.

Built for AI agents first: `skills/artifacto/SKILL.md` teaches Claude Code, Cursor
or anything else that can run `curl` to publish and then update the same link.

## Why two domains

Artifacto hosts **arbitrary third-party HTML with JavaScript**, uploaded by anyone.
Isolation is the architecture, not a setting:

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

Artifacts are served under a policy that blocks `fetch`, form submission, top-level
navigation, popups, downloads and every external resource. An artifact cannot link
out at all — it is a closed page. `allow_network=true` opens `connect-src` for one
artifact and nothing else. See `RawController`.

Uploaded HTML is never sanitized — stripping `<script>` would break every
interactive artifact. Markdown is different: we render it, so it is sanitized and
gets a much stricter policy.

## Local development

Artifact subdomains default to `*.usercontent.localhost`, which browsers resolve
to 127.0.0.1 with no `/etc/hosts` editing. The app is on plain `localhost`.

```bash
bin/setup
bin/rails server -p 3000
```

Then open <http://localhost:3000>. Artifacts appear at
`http://<slug>.usercontent.localhost:3000/`.

If port 3000 is taken, pass the port in both places so generated URLs match:

```bash
PORT=3100 bin/rails server -p 3100
```

Run the suite — it covers the isolation headers, so a regression there fails the build:

```bash
bin/rails test
```

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `APP_ORIGIN` | `http://localhost:$PORT` | Origin used in `frame-ancestors` and in returned URLs. **Required in production** |
| `CONTENT_HOST` | `usercontent.localhost` | Parent domain for artifact subdomains |
| `SECRET_KEY_BASE` | — | **Required in production.** There are no encrypted credentials; every secret is an env var |
| `DATABASE_URL` | — | Merged over `config/database.yml` when set |
| `REDIS_URL` | `redis://localhost:6379/0` | Sidekiq queue and cron |
| `SIDEKIQ_IN_PUMA` | unset | Run Sidekiq inside Puma. Single-process Puma only |
| `SIDEKIQ_CONCURRENCY` | `3` | Sidekiq threads; counted into the Active Record pool |
| `MAX_UPLOAD_BYTES` | `5242880` | Hard upload limit |
| `DEFAULT_TTL_DAYS` | `14` | Default lifetime, 1–30 allowed |
| `IP_HASH_SECRET` | `dev-secret` | HMAC key for `creator_ip_hash`; rotating it orphans existing bans |
| `ADMIN_USER` / `ADMIN_PASSWORD` | `admin` / `change-me` | HTTP Basic for `/admin` |
| `CF_ZONE_ID` / `CF_API_TOKEN` | — | Purge the CDN on update; the purge job no-ops without them |

## Deploy

Any Docker host works — the image reads everything from env vars, so there is no
`master.key` to ship. Set at minimum `SECRET_KEY_BASE`, `APP_ORIGIN`,
`CONTENT_HOST`, `DATABASE_URL` (or the `DB_*` vars), `REDIS_URL`,
`SIDEKIQ_IN_PUMA=true` and the three `AR_ENCRYPTION_*` keys.

Generate the secrets once:

```bash
bin/rails secret   # SECRET_KEY_BASE, AR_ENCRYPTION_*, IP_HASH_SECRET
```

`config/deploy.yml` still describes a Kamal deploy onto one small box: Postgres
and Valkey run as accessories next to the app, and Sidekiq runs inside Puma.

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

## Not built yet

- **Comments** — the wrapper page and the injected `artifact_agent.js` already
  exchange `artifacto:*` messages over `postMessage`. The overlay, the `comments`
  table and `GET /api/v1/artifacts/:slug/comments` are the next phase, and are the
  actual point of the product: an artifact whose reader feedback comes back to the
  agent that wrote it.
- Accounts and a dashboard (`artifacts.user_id` is already there).
- Version history and rollback.
