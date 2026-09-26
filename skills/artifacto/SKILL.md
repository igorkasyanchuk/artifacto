---
name: artifacto
description: Publish a self-contained HTML or Markdown file to Artifacto and get a shareable public link, then read the comments readers leave on it. Use when the user asks to share, publish, host, or send someone a page, report, dashboard, chart, or mockup you just generated; when they ask to update or take down a page you published earlier; and when they ask what feedback a published page has received.
---

# Artifacto

Uploads one self-contained file and returns a public URL. No account, no login.

- **Limit:** 5 MB. Everything must be inline — CSS, JS, images as `data:` URIs.
  External URLs are blocked by the serving policy and will silently fail to load.
  **This includes web fonts.** A `<link>` to Google Fonts is dropped without an
  error and the page silently falls back, so use system font stacks, or inline the
  face as a `@font-face` `data:` URI. Habits carried over from other artifact
  hosts, which do allow a font CDN, break here.
- **Lifetime:** 14 days by default, 1–30 allowed. Extendable.
- **Sandbox:** artifacts cannot make network requests unless uploaded with
  `allow_network=true`, and can never submit a form, open a new tab, offer a
  download, or link to an external site. Build the page to stand on its own —
  outbound links will not work.

Set `ARTIFACTO_URL` if self-hosting; it defaults to `https://artifacto.igorkasyanchuk.com`. That
default is not always the instance you want: an instance serves this file at
`/skill` with its own host already substituted, so a copy fetched from there is
correct, while a copy taken from the repo still points at the public default. If a request
comes back with status `000`, the host never answered — that is DNS or a wrong
base URL, not the API. Confirm the base before retrying, and ask the user which
instance to publish to rather than guessing:

```bash
curl -s -o /dev/null -w "%{http_code}\n" --max-time 10 "${ARTIFACTO_URL:-https://artifacto.igorkasyanchuk.com}/up"
```

## Publish first, verify rarely

Once the file is written, upload it. Do not open a browser, screenshot it, or spin
up a preview to check that it renders — that is what the reader's comments are for,
and a round of self-inspection costs more than the one line a reader would have
written. A preview also takes over the user's screen, so it interrupts them to buy
something they were going to tell you anyway.

Two exceptions, and nothing else: the user asked for a visual check, or the change
was structural enough that a silent break is likely — a layout rewritten from
scratch, a new grid or template, a switch of the whole page's markup. Content edits,
copy changes, colour and spacing tweaks, added sections: upload them unseen.

The loop is: upload, hand over the URL, stop. When the user comes back — "any
feedback yet?" — fetch the comments, apply them, `PUT` the same URL, delete the
comments you acted on. Then stop again.

**Acting on a comment means publishing.** Editing the local file is half the job:
a fix that has not been `PUT` does not exist as far as the reader is concerned, and
they are looking at the link, not at your working copy. So `PUT` by default after
every round of fixes, without being asked to, and only then report what changed.

Two checks are still worth doing before upload, because neither needs a browser and
both fail silently in one: every asset is inline, and nothing links out.

## Upload

```bash
curl -sS -w '\n%{http_code}\n' "${ARTIFACTO_URL:-https://artifacto.igorkasyanchuk.com}/api/v1/artifacts" \
  -F "file=@report.html" \
  -F "title=Q3 report" \
  -F "expires_in_days=14"
```

Every failure answers with a JSON body explaining itself, so keep it visible: `-f`
discards that body and leaves nothing but an exit code to guess from.

Use `-F "format=markdown"` for a `.md` file — it is rendered and styled server-side.
Add `-F "allow_network=true"` only if the page genuinely fetches data at runtime.
Add `-F "pin=…"` (at least 6 characters) to require a PIN before the page can be viewed.

Always send the file with `-F file=@…` (multipart). A form field larger than
4 MB is rejected by the server's request parser before it reaches the app.

The response is JSON:

```json
{
  "slug": "k3Fp9wQz2mVnB7xLd4Rs1T",
  "url": "https://artifacto.igorkasyanchuk.com/a/k3Fp9wQz2mVnB7xLd4Rs1T",
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
BASE="${ARTIFACTO_URL:-https://artifacto.igorkasyanchuk.com}/api/v1/artifacts/$SLUG"

curl -sS -X PUT    -H "Authorization: Bearer $TOKEN" -F "file=@report.html" -F "expires_in_days=30" "$BASE"
curl -sS -X PATCH  -H "Authorization: Bearer $TOKEN" -F "expires_in_days=30" "$BASE/extend"
curl -sS -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE"
```

`PUT` keeps the same URL and resets the expiry clock — to the default lifetime,
not to the one the artifact already had. A `PUT` without `expires_in_days` silently
shortens a 30-day artifact back to 14, so carry the value on every update.

**An update is not visible instantly.** Artifacts are served `max-age=300`, so a
browser that already has the page keeps its own copy for five minutes and never
asks the server. A user reporting "I don't see the update" is almost always looking
at that cache — tell them to hard-reload rather than publishing again. To check what
the server actually holds, compare `last-modified` on the artifact's `raw_url`
against the time of your `PUT` (`TOKEN` and `BASE` as above):

```bash
RAW_URL=$(curl -sS -H "Authorization: Bearer $TOKEN" "$BASE" | jq -r .raw_url)
curl -sSI "$RAW_URL" | grep -i 'last-modified\|etag'
```

## Building the page

Everything below follows from one header. This is the policy an artifact is served
under — read it as the build spec, not as trivia:

```
default-src 'none';   script-src 'unsafe-inline';   style-src 'unsafe-inline'
img-src data: blob:;  font-src data:;  media-src data: blob:
connect-src 'none';   form-action 'none';   base-uri 'none'
frame-ancestors 'self' APP_ORIGIN
sandbox allow-scripts allow-modals
```

`default-src 'none'` is the whole story: nothing loads from anywhere. Inline script
and inline style are the only reason the page runs at all, and images, fonts and
media must arrive as `data:` URIs.

**What silently does nothing.** None of these error usefully — they just fail:

| You wrote | What happens |
|---|---|
| `<link href="https://fonts.googleapis.com/…">` | blocked; the page falls back to a system font and looks subtly wrong |
| `<script src="https://cdn…/chart.js">` | blocked; every chart is an empty box |
| `<img src="https://…">` | blocked; use a `data:` URI |
| `fetch()`, `XMLHttpRequest`, `WebSocket` | blocked by `connect-src 'none'` unless the artifact was uploaded with `allow_network=true` |
| `<form>` submit, `mailto:` | blocked by `form-action 'none'` |
| `<a href="https://…">`, `target="_blank"`, `window.open` | no top-level navigation and no popups: an artifact cannot take the viewer anywhere |
| a download link, `<a download>` | no `allow-downloads` in the sandbox |
| `localStorage`, `sessionStorage`, `IndexedDB` | **throws** on an instance in single-origin mode, where the sandbox withholds `allow-same-origin`. Never assume it exists |

Storage is the one that throws rather than no-ops, so it takes a real guard:

```js
function store(key, value) {
  try { localStorage.setItem(key, value); } catch (e) { /* opaque origin */ }
}
```

### Charts and SVG

No chart library is reachable, so **compute the geometry when you write the file and
bake the numbers into the markup.** Hand-authored inline SVG is the whole toolkit.

- `<svg viewBox="0 0 640 120">` plus `svg { width: 100%; height: auto }` scales
  correctly at any width. Set `min-width` on a scroll container for wide charts.
- CSS custom properties work in SVG presentation attributes — `fill="var(--c-1)"`
  resolves — so charts stay on the page's token system.
- A `<title>` child of a shape gives a native hover tooltip with no JavaScript, and
  it is what screen readers read. Put a `role="img"` and an `aria-label` on the
  `<svg>` itself describing what the chart shows.
- Give every figure a `<figcaption>` that restates the values as text. It is the
  table view, the print fallback, and the thing that survives when colour does not.
- Label the marks directly. A legend is for two or more series; one series is named
  by the title.
- If the numbers are synthetic, **say so on the chart**, not only in your message.
  A page that carries unlabelled fake telemetry is a page that lies to its reader.

### CSS

- Put the palette in `:root` as tokens and style everything through them, so a
  colour is never defined only inside a media query or a `[data-theme]` block.
- `body` must paint its own `background` from a token. A transparent body borrows
  whatever the viewer's chrome is painting behind it.
- Either design both themes through `prefers-color-scheme`, or commit to one and
  paint every colour explicitly. A half-themed page renders one theme's text on the
  other theme's ground.
- **Watch selector specificity in layout rules.** `section > *` is (0,1,1) and beats
  a plain `.rail` at (0,1,0), so a blanket child rule will quietly override the
  per-element placement you wrote afterwards. Wrap the blanket rule in `:where()` —
  `:where(section) > * { … }` is (0,0,0) and loses to every class, which is what you
  want.
- Wide content — tables, code, diagrams — scrolls inside its own
  `overflow-x: auto` container so the page body never scrolls sideways.

### Fonts

No font host is reachable. Use system stacks:

```css
--sans: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
--serif: "Iowan Old Style", Charter, "Palatino Linotype", Palatino, Georgia, serif;
--mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;
```

A specific face has to be embedded as a `@font-face` with a `data:` URI, which costs
real bytes against the 5 MB cap — worth it rarely, and never for a body face.

### JavaScript

Inline `<script>` runs. Modules from a CDN do not, and neither does anything with a
`src`. Browser APIs that touch no network are all available: `IntersectionObserver`,
Canvas, WebGL, `matchMedia`, `requestAnimationFrame`.

- Honour `prefers-reduced-motion: reduce` for every animation.
- Never make content depend on script. If an element starts at `opacity: 0` and a
  script reveals it, one thrown exception hides that content permanently.
- The page already carries an injected hook that talks to the wrapper over
  `postMessage`. Do not add your own listener for `artifacto:*` messages, and do not
  postMessage to the parent yourself.

### Two policies, not one

The header above governs the artifact. The app origin — the wrapper page around it —
runs a **separate, stricter** policy of its own: `script-src 'self'` with a
per-request nonce, `style-src 'self'`, `connect-src 'self'`. Nothing you put in an
artifact can relax it, and a CSP error naming `turbo`, `stimulus` or the app's own
assets comes from that page, not from yours. Reading a console error inside the
frame, check which document it came from before changing the artifact.

## Read the comments

Readers annotate the published page in place — they click a spot and type. That
feedback is the reason to publish here rather than anywhere else: read it, fix the
page, `PUT` the same URL.

```bash
curl -sS "${ARTIFACTO_URL:-https://artifacto.igorkasyanchuk.com}/api/v1/artifacts/$SLUG/comments"
```

```json
{
  "comments": [
    {
      "id": 12,
      "selector": "body > div:nth-of-type(2) > p",
      "quote": "Churn is the number that needs a chart here.",
      "anchor_x": 0.42,
      "anchor_y": 0.18,
      "author": "Dana",
      "body": "Can we see this as a bar chart?",
      "created_at": "2026-08-24T16:39:19Z"
    }
  ]
}
```

`anchor_x` and `anchor_y` are where inside that element the reader clicked, as a
fraction of its box. They exist so the overlay can draw the pin back on the spot
rather than on the element's corner, and are `null` on comments left before the
overlay recorded them — nothing outside the wrapper needs them.

`author` is the name the reader typed, and is `null` when they left the box
empty — nothing verifies it, so read it as a label on a thread, not as identity.

`quote` is the text the reader clicked on — use it to find the spot, not `selector`,
which is a CSS path into the version of the page that was live when they commented.

No token needed to read — unless the artifact has a PIN, in which case pass
`-H "Authorization: Bearer $TOKEN"`, which outranks the PIN. When the user asks
"any feedback yet?", this is the call.
After acting on a comment, clear it so it does not come back next time:

```bash
curl -sS -X DELETE -H "Authorization: Bearer $TOKEN" \
  "${ARTIFACTO_URL:-https://artifacto.igorkasyanchuk.com}/api/v1/artifacts/$SLUG/comments/$ID"
```

Comments survive a `PUT` — updating the page does not wipe the feedback on it.

## Metadata

```bash
curl -sS "${ARTIFACTO_URL:-https://artifacto.igorkasyanchuk.com}/api/v1/artifacts/$SLUG"
```

Returns title, size, view count, comment count and expiry. No token needed — unless
the artifact has a PIN, in which case pass `-H "Authorization: Bearer $TOKEN"`.

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
