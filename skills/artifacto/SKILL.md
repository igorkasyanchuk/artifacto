---
name: artifacto
description: Publish a self-contained HTML or Markdown file to Artifacto and get a shareable public link, then read the comments readers leave on it. Use when the user asks to share, publish, host, or send someone a page, report, dashboard, chart, or mockup you just generated; when they ask to update or take down a page you published earlier; and when they ask what feedback a published page has received.
---

# Artifacto

Uploads one self-contained file and returns a public URL. No account, no login.

- **Limit:** 5 MB. Everything must be inline — CSS, JS, images as `data:` URIs.
  External URLs are blocked by the serving policy and will silently fail to load.
- **Lifetime:** 14 days by default, 1–30 allowed. Extendable.
- **Sandbox:** artifacts cannot make network requests unless uploaded with
  `allow_network=true`, and can never submit a form, open a new tab, offer a
  download, or link to an external site. Build the page to stand on its own —
  outbound links will not work.

Set `ARTIFACTO_URL` if self-hosting; it defaults to `https://artifacto.app`.

## Upload

```bash
curl -sf "${ARTIFACTO_URL:-https://artifacto.app}/api/v1/artifacts" \
  -F "file=@report.html" \
  -F "title=Q3 report" \
  -F "expires_in_days=14"
```

Use `-F "format=markdown"` for a `.md` file — it is rendered and styled server-side.
Add `-F "allow_network=true"` only if the page genuinely fetches data at runtime.
Add `-F "pin=1234"` to require a PIN before the page can be viewed.

Always send the file with `-F file=@…` (multipart). A form field larger than
4 MB is rejected by the server's request parser before it reaches the app.

The response is JSON:

```json
{
  "slug": "k3Fp9wQz2mVnB7xLd4Rs1T",
  "url": "https://artifacto.app/a/k3Fp9wQz2mVnB7xLd4Rs1T",
  "raw_url": "https://k3Fp9wQz2mVnB7xLd4Rs1T.artifactousercontent.com/",
  "edit_token": "…",
  "expires_at": "2026-09-06T12:00:00Z"
}
```

Give the user `url`. `raw_url` is the unwrapped page, useful for embedding.

## Remember the token

`edit_token` is shown exactly once and is the only way to change the artifact later.

After a successful upload, write it to `.artifacto/<name>.json` in the project root:

```json
{ "slug": "…", "edit_token": "…", "url": "…" }
```

and make sure `.artifacto/` is listed in `.gitignore`.

Before publishing anything, check whether `.artifacto/` already holds an entry for
this page. If it does, **update that artifact** instead of creating a new one — the
user has already shared that link.

## Update, extend, delete

```bash
TOKEN=$(jq -r .edit_token .artifacto/report.json)
SLUG=$(jq -r .slug .artifacto/report.json)
BASE="${ARTIFACTO_URL:-https://artifacto.app}/api/v1/artifacts/$SLUG"

curl -sf -X PUT    -H "Authorization: Bearer $TOKEN" -F "file=@report.html" "$BASE"
curl -sf -X PATCH  -H "Authorization: Bearer $TOKEN" -F "expires_in_days=30" "$BASE/extend"
curl -sf -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE"
```

`PUT` keeps the same URL and resets the expiry clock.

## Read the comments

Readers annotate the published page in place — they click a spot and type. That
feedback is the reason to publish here rather than anywhere else: read it, fix the
page, `PUT` the same URL.

```bash
curl -sf "${ARTIFACTO_URL:-https://artifacto.app}/api/v1/artifacts/$SLUG/comments"
```

```json
{
  "comments": [
    {
      "id": 12,
      "selector": "body > div:nth-of-type(2) > p",
      "quote": "Churn is the number that needs a chart here.",
      "body": "Can we see this as a bar chart?",
      "created_at": "2026-08-24T16:39:19Z"
    }
  ]
}
```

`quote` is the text the reader clicked on — use it to find the spot, not `selector`,
which is a CSS path into the version of the page that was live when they commented.

No token needed to read — unless the artifact has a PIN, in which case pass
`-H "Authorization: Bearer $TOKEN"`, which outranks the PIN. When the user asks
"any feedback yet?", this is the call.
After acting on a comment, clear it so it does not come back next time:

```bash
curl -sf -X DELETE -H "Authorization: Bearer $TOKEN" \
  "${ARTIFACTO_URL:-https://artifacto.app}/api/v1/artifacts/$SLUG/comments/$ID"
```

Comments survive a `PUT` — updating the page does not wipe the feedback on it.

## Metadata

```bash
curl -sf "${ARTIFACTO_URL:-https://artifacto.app}/api/v1/artifacts/$SLUG"
```

Returns title, size, view count, comment count and expiry. No token needed.

## Errors

| Status | Meaning |
|---|---|
| 401 | Wrong or missing edit token |
| 404 | No such artifact |
| 410 | Expired and deleted — upload a fresh one |
| 413 | Over 5 MB — inline fewer or smaller images |
| 422 | Empty body, invalid UTF-8, or `expires_in_days` outside 1–30 |
| 429 | Rate limited — wait, do not retry in a loop |
| 451 | Blocked: taken down after an abuse report, or byte-identical to something already taken down |
