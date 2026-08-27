import { Controller } from "@hotwired/stimulus"

// The reader's name, not their identity: nothing checks it, and it is kept on
// this browser so the same person does not retype it on every artifact.
const AUTHOR_KEY = "artifacto:author"

// Storage is a convenience here — a remembered name, a remembered edit token —
// and every access to it throws outright where the browser has denied it. None
// of that is worth taking the overlay down for, least of all in connect(), where
// the throw would land before the message listener is attached and leave the
// page with no comments at all.
const recall = (key) => { try { return localStorage.getItem(key) } catch { return null } }
const remember = (key, value) => {
  try { value ? localStorage.setItem(key, value) : localStorage.removeItem(key) } catch { /* denied */ }
}

// Comment overlay: the app-origin half of the channel opened by artifact_agent.js.
//
// The frame resolves anchors and reports coordinates; every comment body lives
// here and is written with textContent, so reader text never becomes markup and
// never crosses back into the artifact.
export default class extends Controller {
  static targets = [
    "frame", "overlay", "panel", "quote", "list", "body", "author", "count", "toggle", "error",
    "drawer", "entries"
  ]
  static values = { slug: String, token: String }

  connect() {
    this.pins = new Map()
    this.groups = new Map()
    this.placed = new Set()
    this.mode = false
    if (this.hasAuthorTarget) this.authorTarget.value = recall(AUTHOR_KEY) || ""
    this.onMessage = this.onMessage.bind(this)
    window.addEventListener("message", this.onMessage)
    if (this.hasFrameTarget) this.load()
  }

  disconnect() {
    clearTimeout(this.anchorTimeout)
    window.removeEventListener("message", this.onMessage)
  }

  copy() { navigator.clipboard.writeText(window.location.href) }

  // <details> has no light dismiss of its own, so a menu left open keeps sitting
  // over the artifact until the reader thinks to press ⋯ again.
  dismissMenu(event) {
    const menu = this.element.querySelector(".menu[open]")
    if (!menu) return
    if (event.target instanceof Node && menu.contains(event.target)) return

    menu.open = false
  }

  // The token is only present on a PIN-locked artifact, and only after the PIN
  // has been entered. It expires well before the page does, so a comment posted
  // hours later fails with 401 rather than silently escaping the lock.
  url(suffix = "") {
    const base = `/api/v1/artifacts/${this.slugValue}/comments${suffix}`
    return this.tokenValue ? `${base}?t=${encodeURIComponent(this.tokenValue)}` : base
  }

  get endpoint() { return this.url() }

  note(text) {
    this.countTarget.textContent = text
    this.countTarget.hidden = !text
  }

  async load() {
    const response = await fetch(this.endpoint, { headers: { Accept: "application/json" } })

    if (!response.ok) {
      // A locked artifact whose unlock token has run out. Say so: the iframe
      // keeps rendering from cache, so nothing else on the page would hint that
      // this is a lapsed session rather than an artifact nobody has commented on.
      if (response.status === 401) this.note("comments locked — reload to enter the PIN again")
      return
    }

    const { comments } = await response.json()

    // One pin per anchor point, so replies to the same spot stack into a thread.
    // Grouping on the selector string means an edit that splits a selector splits
    // the thread too — the quote fallback still finds the text, which is the part
    // a reader cares about.
    this.groups = new Map()
    for (const comment of comments) {
      const group = this.groups.get(comment.selector) ||
        { key: comment.selector, selector: comment.selector, quote: comment.quote, comments: [] }
      group.comments.push(comment)
      this.groups.set(comment.selector, group)
    }

    this.note(comments.length ? (comments.length === 1 ? "1 comment" : `${comments.length} comments`) : "")
    this.drawPins()
    this.drawEntries()
    this.sendAnchors()
  }

  drawPins() {
    this.overlayTarget.replaceChildren()
    this.pins.clear()
    this.placed.clear()
    this.attempts = 0

    for (const group of this.groups.values()) {
      const pin = document.createElement("button")
      pin.type = "button"
      pin.className = "pin"
      pin.hidden = true
      pin.textContent = group.comments.length
      pin.title = group.quote || ""
      pin.addEventListener("click", () => this.openPanel({ ...group, x: pin.offsetLeft, y: pin.offsetTop }))
      this.overlayTarget.append(pin)
      this.pins.set(group.key, pin)
    }
  }

  place(positions) {
    let detached = 0

    for (const position of positions) {
      const pin = this.pins.get(position.key)
      if (!pin) continue

      // Recorded per pin, not as one "the frame answered" flag: the frame also
      // answers the empty anchor list sent before the comments have loaded, and
      // that reply must not count as having placed anything.
      this.placed.add(position.key)

      // A zero box is not proof the element is off-screen: it is equally what an
      // unlaid-out or display:none element measures, and hiding on that reading
      // loses the comment entirely. Only a real box can place a pin, or rule
      // that its element has scrolled past the top or left edge and should go
      // with it rather than clamp to that edge and appear to mark what is there.
      const measured = position.found && (position.width > 0 || position.height > 0)

      if (measured && (position.y + position.height <= 0 || position.x + position.width <= 0)) {
        pin.hidden = true
        continue
      }

      // Anything we cannot place parks in the corner instead of vanishing: the
      // comment still exists and still has to be reachable. A placed one is
      // nudged into the margin so the pin does not cover the text it marks, and
      // clamped only when its element straddles the edge.
      const x = measured ? Math.max(0, position.x - 20) : 8 + detached * 28
      const y = measured ? Math.max(0, position.y - 2) : 8
      if (!measured) detached += 1

      pin.classList.toggle("is-detached", !measured)
      pin.classList.toggle("is-moved", measured && !!position.moved)
      pin.style.left = `${x}px`
      pin.style.top = `${y}px`
      pin.hidden = false
    }
  }

  onMessage(event) {
    // Every artifact has its own origin, so identity comes from the frame, not event.origin.
    if (!this.hasFrameTarget || event.source !== this.frameTarget.contentWindow) return
    const data = event.data
    if (!data || typeof data.type !== "string" || !data.type.startsWith("artifacto:")) return

    if (data.type === "artifacto:ready") this.sendAnchors()
    else if (data.type === "artifacto:anchor") this.openPanel({ selector: data.selector, quote: data.quote, x: data.x, y: data.y })
    else if (data.type === "artifacto:positions" && Array.isArray(data.positions)) this.place(data.positions)
  }

  // targetOrigin "*": in single-origin mode the frame has an opaque origin and
  // cannot be named. What goes over it is the selectors and quotes the frame
  // handed us in the first place — never a comment body.
  post(message) {
    if (!this.hasFrameTarget) return
    this.frameTarget.contentWindow?.postMessage(message, "*")
  }

  sendAnchors() {
    this.post({
      type: "artifacto:anchors",
      anchors: [ ...this.groups.values() ].map(({ key, selector, quote }) => ({ key, selector, quote }))
    })

    clearTimeout(this.anchorTimeout)
    if (!this.groups.size) return

    this.attempts += 1
    this.anchorTimeout = setTimeout(() => this.chase(), 1000)
  }

  // Nothing acknowledges an anchors message, so the pins are the receipt. The
  // frame attaches its listener while its document parses, and this page can
  // easily send before that — a lost message would otherwise leave the frame
  // with no anchors at all, which nothing recovers from because it never asks.
  // So: ask again while any pin is unplaced, and only then admit defeat and show
  // them detached, which is what a pre-hook or a deliberately silent artifact
  // deserves. Detached still opens its thread; invisible does not.
  chase() {
    const unplaced = [ ...this.groups.keys() ].filter((key) => !this.placed.has(key))
    if (!unplaced.length) return

    if (this.attempts < 3) return this.sendAnchors()

    this.place(unplaced.map((key) => ({ key, found: false })))
  }

  toggle() {
    this.mode = !this.mode
    this.post({ type: "artifacto:mode", comment: this.mode })
    this.toggleTarget.classList.toggle("primary", this.mode)
    this.toggleTarget.textContent = this.mode ? "Click a spot…" : "Comment"
    if (!this.mode) this.close()
  }

  openPanel({ selector, quote, comments = [], x, y }) {
    this.pending = { selector, quote }
    this.errorTarget.hidden = true
    this.quoteTarget.textContent = quote ? `“${quote.slice(0, 80)}”` : "this spot"
    this.listTarget.replaceChildren(...comments.map((comment) => this.commentNode(comment)))

    const box = this.overlayTarget.getBoundingClientRect()
    this.panelTarget.hidden = false

    // Keep the panel inside the stage. A stage that has not been laid out yet
    // measures zero, and clamping against that would pin every panel to the
    // corner — so in that case there is nothing to clamp against.
    const maxLeft = box.width ? Math.max(8, box.width - this.panelTarget.offsetWidth - 8) : Infinity
    const maxTop = box.height ? Math.max(8, box.height - this.panelTarget.offsetHeight - 8) : Infinity
    this.panelTarget.style.left = `${Math.min(Math.max(8, x || 0), maxLeft)}px`
    this.panelTarget.style.top = `${Math.min(Math.max(8, y || 0), maxTop)}px`
    this.bodyTarget.value = ""
    this.bodyTarget.focus()
  }

  // The drawer prints the byline on its own meta row, so it asks for the body alone.
  commentNode(comment, byline = true) {
    const item = document.createElement("p")
    item.className = "comment"
    item.textContent = comment.body
    if (byline) {
      const when = document.createElement("span")
      when.className = "note"
      when.textContent = ` — ${this.by(comment)}`
      item.append(when)
    }
    return item
  }

  by(comment) {
    return `${comment.author || "anonymous"}, ${new Date(comment.created_at).toLocaleDateString()}`
  }

  close() {
    this.panelTarget.hidden = true
    this.pending = null
  }

  async submit(event) {
    event.preventDefault()
    const body = this.bodyTarget.value.trim()
    if (!body || !this.pending) return

    const author = this.hasAuthorTarget ? this.authorTarget.value.trim() : ""
    remember(AUTHOR_KEY, author)

    const response = await fetch(this.endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ ...this.pending, body, author })
    })

    if (!response.ok) {
      const { error } = await response.json().catch(() => ({}))
      this.errorTarget.textContent = response.status === 401
        ? "This artifact is locked. Reload the page and enter the PIN again."
        : error || `Could not save that comment (${response.status}).`
      this.errorTarget.hidden = false
      return
    }

    this.close()
    this.load()
  }

  // Side panel: every comment on the artifact, including the ones whose anchor
  // no longer resolves and whose pin is therefore parked in the corner.
  drawer() {
    this.drawerTarget.hidden = !this.drawerTarget.hidden
  }

  drawEntries() {
    if (!this.hasEntriesTarget) return

    const entries = [ ...this.groups.values() ]
      .flatMap((group) => group.comments.map((comment) => this.entryNode(group, comment)))

    if (!entries.length) {
      const empty = document.createElement("p")
      empty.className = "empty"
      empty.textContent = "No comments yet. Click Comment, then click a spot in the page."
      entries.push(empty)
    }

    this.entriesTarget.replaceChildren(...entries)
  }

  entryNode(group, comment) {
    const entry = document.createElement("article")
    entry.className = "entry"

    // A real button, not just the clickable card below it: this is the only way
    // to reach a thread whose pin has scrolled out of view, so it has to be
    // reachable by keyboard too.
    const quote = document.createElement("button")
    quote.type = "button"
    quote.className = "note quote"
    quote.textContent = group.quote ? `“${group.quote.slice(0, 80)}”` : "this spot"
    quote.addEventListener("click", (event) => { event.stopPropagation(); this.jump(group) })

    const meta = document.createElement("p")
    meta.className = "meta"
    const who = document.createElement("span")
    who.className = "note"
    who.textContent = this.by(comment)
    const spacer = document.createElement("span")
    spacer.className = "spacer"
    const remove = document.createElement("button")
    remove.type = "button"
    remove.textContent = "Delete"
    remove.addEventListener("click", (event) => { event.stopPropagation(); this.destroy(comment) })
    meta.append(who, spacer, remove)

    entry.append(quote, this.commentNode(comment, false), meta)
    entry.addEventListener("click", () => this.jump(group))
    return entry
  }

  jump(group) {
    const pin = this.pins.get(group.key)
    this.openPanel({ ...group, x: pin?.offsetLeft ?? 8, y: pin?.offsetTop ?? 8 })
  }

  // ponytail: prompt() + localStorage, not a login. The edit token handed out at
  // upload is the only owner proof this page can have — accounts do not own
  // artifacts yet, so there is nothing else to check a delete against.
  async destroy(comment) {
    const key = `artifacto:token:${this.slugValue}`
    const token = recall(key) ||
      window.prompt("Paste this artifact's edit token to delete comments.\nIt was shown when the file was uploaded.")?.trim()
    if (!token) return
    if (!window.confirm("Delete this comment?")) return

    const response = await fetch(this.url(`/${comment.id}`), {
      method: "DELETE",
      headers: { Authorization: `Bearer ${token}`, Accept: "application/json" }
    })

    if (response.status === 401) {
      remember(key, null)
      window.alert("That edit token was not accepted.")
      return
    }

    if (!response.ok) return window.alert(`Could not delete that comment (${response.status}).`)

    remember(key, token)
    this.close()
    this.load()
  }
}
