import { Controller } from "@hotwired/stimulus"

// The reader's name, not their identity: nothing checks it, and it is kept on
// this browser so the same person does not retype it on every artifact.
const AUTHOR_KEY = "artifacto:author"

const FLASH_MS = 2500

// "3h ago" for the byline, the full date in its title.
const RELATIVE = new Intl.RelativeTimeFormat(undefined, { numeric: "auto", style: "narrow" })
const UNITS = [ [ "year", 31536000 ], [ "month", 2592000 ], [ "day", 86400 ], [ "hour", 3600 ], [ "minute", 60 ] ]
const ago = (date) => {
  // Clamped: a server clock ahead of this one must not print "in 3 min".
  const seconds = Math.min(0, (date - Date.now()) / 1000)
  const [ unit, size ] = UNITS.find(([ , size ]) => Math.abs(seconds) >= size) || [ "second", 1 ]
  return Math.abs(seconds) < 45 ? "just now" : RELATIVE.format(Math.round(seconds / size), unit)
}

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
    "drawer", "entries", "toast", "pins", "status", "listToggle"
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
    clearTimeout(this.toastTimeout)
    window.removeEventListener("message", this.onMessage)
  }

  // Copying is invisible by definition: nothing on the page changes, so without a
  // word back the reader cannot tell a copy from a dead button.
  async copy() {
    try {
      await navigator.clipboard.writeText(window.location.href)
      this.flash("Link copied.")
    } catch {
      this.flash("Could not copy — the link is in the address bar.")
    }
  }

  // Escape backs out one layer at a time, outermost first: the report menu, then
  // the thread, then the drawer, and only then comment mode itself. A keypress
  // inside the frame never reaches this document, but every one of these layers
  // leaves focus on this side — the thread focuses its own textarea — so there is
  // nothing to forward and no reason to touch the artifact's hook for it.
  //
  // c / l / p are the bar's shortcuts, and only while nobody is typing: the
  // thread's own fields, and the report form's select, keep their keys.
  key(event) {
    if (event.key === "Escape") return this.escape()
    if (event.metaKey || event.ctrlKey || event.altKey || !this.hasFrameTarget) return
    if (event.target.closest?.("input, textarea, select, [contenteditable]")) return

    const action = { c: "toggle", l: "drawer", p: "togglePins" }[event.key]
    if (!action) return

    event.preventDefault()
    this[action]()
  }

  escape() {
    const menu = this.element.querySelector(".menu[open]")
    if (menu) menu.open = false
    else if (this.hasPanelTarget && !this.panelTarget.hidden) this.close()
    else if (this.hasDrawerTarget && !this.drawerTarget.hidden) this.drawer()
    else if (this.mode) this.toggle()
  }

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
    this.statusTarget.textContent = text
    this.statusTarget.hidden = !text
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

      // The pin belongs to the spot, and the spot is where the first comment
      // that recorded one was left; later replies stack onto that pin rather
      // than dragging it somewhere new. First *recorded* rather than simply
      // first, because a thread started before the anchor point existed would
      // otherwise hold the whole group at its element's corner forever.
      if (group.fx == null && comment.anchor_x != null) {
        group.fx = comment.anchor_x
        group.fy = comment.anchor_y
      }

      this.groups.set(comment.selector, group)
    }

    this.countTarget.textContent = comments.length
    this.countTarget.hidden = !comments.length
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
      pin.setAttribute("aria-label", `${group.comments.length} on “${(group.quote || "this spot").slice(0, 40)}”`)
      pin.addEventListener("click", () => this.openPanel({ ...group, x: pin.offsetLeft + 28, y: pin.offsetTop }))
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

      // Where the pin wants to be: the recorded spot inside the element, or the
      // element's own corner for a comment left before spots were recorded.
      const group = this.groups.get(position.key)
      const anchored = group?.fx != null
      const px = position.x + this.offset(group?.fx, position.width)
      const py = position.y + this.offset(group?.fy, position.height)

      // What counts as gone depends on what the pin stands for. A recorded spot
      // is a point, so the point itself decides — otherwise a comment left far
      // down a page rides the clamp below up to the top edge as soon as the
      // reader scrolls past it, and marks whatever happens to be there. Without
      // a spot the pin stands for the whole element, which is only gone once its
      // far edge has passed the top or left.
      const gone = anchored
        ? py < 0 || px < 0
        : position.y + position.height <= 0 || position.x + position.width <= 0

      if (measured && gone) {
        pin.hidden = true
        continue
      }

      // Anything we cannot place parks in the corner instead of vanishing: the
      // comment still exists and still has to be reachable. A placed one is
      // offset to the point inside the element that was clicked — without that
      // every comment on a large element, and every comment on <body>, marks
      // that element's top-left corner instead of the spot the reader meant.
      // Then nudged into the margin so the pin does not cover what it marks. The
      // clamp is only ever the nudge coming back: anything genuinely off the top
      // or left has already been ruled gone above.
      const x = measured ? Math.max(0, px - 20) : 8 + detached * 28
      const y = measured ? Math.max(0, py - 2) : 8
      if (!measured) detached += 1

      pin.classList.toggle("is-detached", !measured)
      pin.classList.toggle("is-moved", measured && !!position.moved)
      pin.style.left = `${x}px`
      pin.style.top = `${y}px`
      pin.hidden = false
    }
  }

  // Comments written before the anchor point was recorded have no fraction, and
  // fall back to the element's own corner rather than guessing at a middle.
  offset(fraction, size) {
    return typeof fraction === "number" ? fraction * size : 0
  }

  onMessage(event) {
    // Every artifact has its own origin, so identity comes from the frame, not event.origin.
    if (!this.hasFrameTarget || event.source !== this.frameTarget.contentWindow) return
    const data = event.data
    if (!data || typeof data.type !== "string" || !data.type.startsWith("artifacto:")) return

    if (data.type === "artifacto:ready") this.sendAnchors()
    else if (data.type === "artifacto:anchor") this.compose(data)
    else if (data.type === "artifacto:positions" && Array.isArray(data.positions)) {
      this.place(data.positions)
      if (data.revealed != null && data.revealed === this.revealing) this.landed()
    }
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

  // The mode is shown on this side too — the modeline and the stage outline hang
  // off .is-commenting — because the cursor that says so lives in the frame, and
  // a reader whose pointer is on the bar cannot see it.
  toggle() {
    this.mode = !this.mode
    this.post({ type: "artifacto:mode", comment: this.mode })
    this.element.classList.toggle("is-commenting", this.mode)
    this.toggleTarget.setAttribute("aria-pressed", this.mode)
    if (!this.mode) this.close()
  }

  // A new spot: a ghost pin marks exactly where the click landed, so the reader
  // can see what the comment they are typing will point at.
  compose({ selector, quote, fx, fy, x, y }) {
    this.ghost ||= Object.assign(document.createElement("span"), { className: "pin is-new", textContent: "+" })
    // Same nudge as place(), so the saved pin lands where the ghost stood.
    this.ghost.style.left = `${Math.max(0, x - 20)}px`
    this.ghost.style.top = `${Math.max(0, y - 2)}px`
    this.overlayTarget.append(this.ghost)
    this.openPanel({ selector, quote, fx, fy, x: x + 32, y: y - 8 })
  }

  // One toast for everything that has something to say and nowhere to say it.
  // Emptying it is what hides it — see .toast:empty. The element is never taken
  // out of the page, because a role="status" region whose text changed while it
  // was display:none is not reliably announced, and for Copy link this toast is
  // the only feedback there is.
  flash(text, ms = FLASH_MS) {
    if (!this.hasToastTarget) return

    this.toastTarget.textContent = text
    clearTimeout(this.toastTimeout)
    this.toastTimeout = setTimeout(() => this.hideToast(), ms)
  }

  hideToast() {
    clearTimeout(this.toastTimeout)
    if (this.hasToastTarget) this.toastTarget.textContent = ""
  }

  openPanel({ key, selector, quote, fx, fy, comments = [], x, y }) {
    if (key != null) this.ghost?.remove()
    this.revealing = null
    for (const [ pinKey, pin ] of this.pins) pin.classList.toggle("is-active", pinKey === key)

    this.pending = { selector, quote, anchor_x: fx, anchor_y: fy }
    this.errorTarget.hidden = true
    this.quoteTarget.textContent = quote ? quote.slice(0, 120) : "this spot"
    this.listTarget.replaceChildren(...comments.map((comment) => this.commentNode(comment)))
    this.listTarget.hidden = !comments.length
    this.bodyTarget.placeholder = comments.length ? "Reply…" : "Leave a comment…"

    this.panelTarget.hidden = false
    this.movePanel(x, y)
    this.bodyTarget.value = ""
    this.bodyTarget.focus()
  }

  movePanel(x, y) {
    const box = this.overlayTarget.getBoundingClientRect()

    // Keep the panel inside the stage. A stage that has not been laid out yet
    // measures zero, and clamping against that would pin every panel to the
    // corner — so in that case there is nothing to clamp against.
    const maxLeft = box.width ? Math.max(8, box.width - this.panelTarget.offsetWidth - 8) : Infinity
    const maxTop = box.height ? Math.max(8, box.height - this.panelTarget.offsetHeight - 8) : Infinity
    this.panelTarget.style.left = `${Math.min(Math.max(8, x || 0), maxLeft)}px`
    this.panelTarget.style.top = `${Math.min(Math.max(8, y || 0), maxTop)}px`
  }

  // Byline row, then the body. Everything the reader wrote goes in as text.
  commentNode(comment) {
    const author = comment.author || "anonymous"
    const created = new Date(comment.created_at)

    const avatar = document.createElement("span")
    avatar.className = "avatar"
    avatar.textContent = [ ...author ][0].toUpperCase()
    const name = document.createElement("b")
    name.textContent = author
    const when = document.createElement("time")
    when.dateTime = comment.created_at
    when.title = created.toLocaleString()
    when.textContent = ago(created)

    const head = document.createElement("div")
    head.className = "comment-head"
    head.append(avatar, name, when)

    const body = document.createElement("p")
    body.className = "comment-body"
    body.textContent = comment.body

    const item = document.createElement("div")
    item.className = "comment"
    item.append(head, body)
    return item
  }

  // Focus left in a hidden textarea would swallow the bar's shortcuts.
  close() {
    if (this.panelTarget.contains(document.activeElement)) document.activeElement.blur()
    this.panelTarget.hidden = true
    this.ghost?.remove()
    for (const pin of this.pins.values()) pin.classList.remove("is-active")
    this.pending = null
    this.revealing = null
  }

  send() { this.panelTarget.requestSubmit() }

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

  // Pins sit on top of somebody else's design, so there has to be a way to get
  // them out of the way and still read the page underneath. Session-only: the
  // next visit starts with the comments visible, which is the point of them.
  togglePins() { this.showPins(this.overlayTarget.hidden) }

  showPins(visible) {
    this.overlayTarget.hidden = !visible
    if (this.hasPinsTarget) this.pinsTarget.setAttribute("aria-pressed", visible)
  }

  // Side panel: every comment on the artifact, including the ones whose anchor
  // no longer resolves and whose pin is therefore parked in the corner.
  drawer() {
    this.drawerTarget.hidden = !this.drawerTarget.hidden
    if (this.hasListToggleTarget) this.listToggleTarget.setAttribute("aria-pressed", !this.drawerTarget.hidden)
  }

  drawEntries() {
    if (!this.hasEntriesTarget) return

    const entries = [ ...this.groups.values() ].map((group) => this.entryNode(group))

    if (!entries.length) {
      const empty = document.createElement("p")
      empty.className = "empty"
      empty.textContent = "No threads yet. Press c, then click any spot on the page."
      entries.push(empty)
    }

    this.entriesTarget.replaceChildren(...entries)
  }

  // One card per thread: the spot, then every comment left on it.
  entryNode(group) {
    const entry = document.createElement("article")
    entry.className = "entry"

    // A real button, not just the clickable card below it: this is the only way
    // to reach a thread whose pin has scrolled out of view, so it has to be
    // reachable by keyboard too.
    const quote = document.createElement("button")
    quote.type = "button"
    quote.className = "quote"
    quote.textContent = group.quote ? group.quote.slice(0, 80) : "this spot"
    quote.addEventListener("click", (event) => { event.stopPropagation(); this.jump(group) })
    entry.append(quote)

    for (const comment of group.comments) {
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "delete"
      remove.textContent = "delete"
      remove.addEventListener("click", (event) => { event.stopPropagation(); this.destroy(comment) })

      const node = this.commentNode(comment)
      node.firstChild.append(remove)
      entry.append(node)
    }

    entry.addEventListener("click", () => this.jump(group))
    return entry
  }

  // The thread opens where its pin is now, and the frame is asked to scroll its
  // spot into view; when the answer comes back, landed() moves the thread along
  // with the pin. A spot that no longer resolves just stays where it is parked.
  jump(group) {
    const pin = this.pins.get(group.key)
    this.showPins(true)
    this.openPanel({ ...group, x: (pin?.offsetLeft ?? 8) + 28, y: pin?.offsetTop ?? 8 })
    this.revealing = group.key
    this.post({ type: "artifacto:reveal", key: group.key, fy: group.fy })
  }

  landed() {
    const pin = this.pins.get(this.revealing)
    this.revealing = null
    if (!pin || pin.hidden || this.panelTarget.hidden) return

    this.movePanel(pin.offsetLeft + 28, pin.offsetTop)
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
