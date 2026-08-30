// Injected into every served artifact. The artifact side of the comment channel:
// it reports where the reader clicked, and it resolves stored anchors back to
// live elements so the wrapper can draw pins over the frame. It never receives a
// comment body — text stays on the app origin.
(function () {
  var PARENT_ORIGIN = "__PARENT_ORIGIN__";

  function send(message) {
    if (window.parent === window) return;
    window.parent.postMessage(message, PARENT_ORIGIN);
  }

  // Stable-ish path: nth-of-type chain up to <body>. Paired with a text quote on
  // the server side, so an edit that breaks the selector can still re-anchor.
  function cssPath(el) {
    var parts = [];
    while (el && el.nodeType === 1 && el !== document.body) {
      var name = el.nodeName.toLowerCase();
      var parent = el.parentNode;
      if (parent) {
        var siblings = [];
        for (var i = 0; i < parent.children.length; i++) {
          if (parent.children[i].nodeName === el.nodeName) siblings.push(parent.children[i]);
        }
        if (siblings.length > 1) name += ":nth-of-type(" + (siblings.indexOf(el) + 1) + ")";
      }
      parts.unshift(name);
      el = parent;
    }
    return "body" + (parts.length ? " > " + parts.join(" > ") : "");
  }

  var commentMode = false;
  var anchors = [];

  function onClick(event) {
    if (!commentMode) return;
    event.preventDefault();
    event.stopPropagation();
    var el = event.target;
    // Where in the element the click landed, as a fraction of its box. The
    // selector alone only ever points at a top-left corner, which is the wrong
    // place for anything big — click the middle of a page and the anchor is
    // <body>, whose corner is the corner of the page. Stored as a fraction, not
    // pixels, so it still means the same spot at another window width.
    var rect = el.getBoundingClientRect();
    send({
      type: "artifacto:anchor",
      selector: cssPath(el),
      quote: (el.textContent || "").trim().slice(0, 200),
      fx: rect.width ? (event.clientX - rect.left) / rect.width : 0,
      fy: rect.height ? (event.clientY - rect.top) / rect.height : 0,
      x: event.clientX,
      y: event.clientY
    });
  }

  function norm(text) {
    return (text || "").replace(/\s+/g, " ").trim();
  }

  function needleFor(anchor) {
    return norm(anchor.quote).slice(0, 60);
  }

  // textContent happily returns the source of a <script>, and an artifact whose
  // script builds the page contains the very text the reader quoted from it —
  // so a quote search over textContent finds the script tag, or <body> through
  // it. Neither is where the reader pointed, and a <script> has no box at all.
  var UNRENDERED = { SCRIPT: 1, STYLE: 1, NOSCRIPT: 1, TEMPLATE: 1, TITLE: 1 };

  function renderedText(el) {
    var out = "";
    for (var i = 0; i < el.childNodes.length; i++) {
      var node = el.childNodes[i];
      if (node.nodeType === 3) out += node.nodeValue;
      else if (node.nodeType === 1 && !UNRENDERED[node.nodeName]) out += renderedText(node);
    }
    return out;
  }

  function says(el, needle) {
    return !needle || norm(renderedText(el)).indexOf(needle) !== -1;
  }

  // An anchor is only really placed if it points at something with a box: a
  // resolve that landed on an invisible element has to stay retryable.
  function anchored(anchor) {
    if (!anchor.el || !anchor.el.isConnected) return false;

    var rect = anchor.el.getBoundingClientRect();
    return rect.width > 0 || rect.height > 0;
  }

  // A PUT replaces the whole body, so an nth-of-type chain written against the
  // old markup will usually miss. The quote is the fallback: find the deepest
  // element still containing that text. Document order puts children after
  // their parents, so the last match is the deepest one.
  function findByQuote(needle) {
    if (!needle) return null;
    var all = document.body ? document.body.querySelectorAll("*") : [];
    var found = null;
    for (var i = 0; i < all.length; i++) {
      if (UNRENDERED[all[i].nodeName]) continue;
      if (norm(renderedText(all[i])).indexOf(needle) !== -1) found = all[i];
    }
    return found;
  }

  // Walks the document, so it runs when anchors arrive, when the page finishes
  // loading, or when a cached element has been torn out — never on scroll.
  // Caches its answer on the anchor as .el / .moved.
  function resolve(anchor) {
    var needle = needleFor(anchor);
    var el = null;
    try { el = document.querySelector(anchor.selector); } catch (e) { el = null; }

    // A selector that still resolves is not proof it resolves to the same thing:
    // insert one paragraph and body > p:nth-of-type(2) points at different text.
    // The quote is what decides, so it is checked even on the happy path.
    if (el && says(el, needle)) {
      anchor.el = el;
      anchor.moved = false;
      return;
    }

    var byQuote = findByQuote(needle);
    if (byQuote) {
      anchor.el = byQuote;
      anchor.moved = true;
      return;
    }

    // Selector still hits, but what it said is nowhere in the page any more.
    // Keep the spot, stop claiming it is the same content.
    anchor.el = el || null;
    anchor.moved = true;
  }

  function resolveAll(onlyMissing) {
    for (var i = 0; i < anchors.length; i++) {
      if (!onlyMissing || !anchored(anchors[i])) resolve(anchors[i]);
    }
  }

  function report() {
    var positions = [];
    for (var i = 0; i < anchors.length; i++) {
      var anchor = anchors[i];

      // Scroll drives this every frame, so the common path must not do more than
      // measure. Only an element that has left the document costs a re-resolve.
      if (anchor.el && !anchor.el.isConnected) resolve(anchor);

      if (!anchor.el) {
        positions.push({ key: anchor.key, found: false });
        continue;
      }

      var rect = anchor.el.getBoundingClientRect();
      positions.push({
        key: anchor.key,
        found: true,
        moved: !!anchor.moved,
        x: rect.left,
        y: rect.top,
        width: rect.width,
        height: rect.height
      });
    }
    send({ type: "artifacto:positions", positions: positions });
  }

  var retryTimer = null;

  // An anchor that resolved to nothing has no element, so the isConnected check
  // in report() can never bring it back. Content that shows up later — a script
  // that renders after load, a tab panel swapped back in — is a DOM mutation, so
  // that is what schedules the retry. Throttled, and skipped outright once every
  // anchor has an element, so a chatty artifact cannot drag the scan back into
  // the hot path.
  function scheduleRetry() {
    if (retryTimer) return;

    var missing = false;
    for (var i = 0; i < anchors.length; i++) {
      if (!anchored(anchors[i])) { missing = true; break; }
    }
    if (!missing) return;

    retryTimer = window.setTimeout(function () {
      retryTimer = null;
      resolveAll(true);
      report();
    }, 500);
  }

  var pending = false;

  function scheduleReport() {
    if (pending || !anchors.length) return;
    pending = true;
    window.requestAnimationFrame(function () {
      pending = false;
      report();
    });
  }

  // A speech bubble, because a crosshair says "precision" and this is a comment.
  // Fixed colours and a white outline for the same reason the pins have them: the
  // artifact's own background is not ours to know. Percent-encoded whole, so the
  // url() needs no quotes and this stays one plain string. Hotspot is the tail
  // tip, which is the point the click actually lands on. crosshair is the
  // fallback for a browser that refuses the image.
  var COMMENT_CURSOR = "url(data:image/svg+xml,%3Csvg%20xmlns=%27http://www.w3.org/2000/svg%27" +
    "%20width=%2728%27%20height=%2728%27%3E%3Cpath%20d=%27M3%203h22v16H14l-6%206v-6H3z%27" +
    "%20fill=%27%232563eb%27%20stroke=%27white%27%20stroke-width=%272%27" +
    "%20stroke-linejoin=%27round%27/%3E%3C/svg%3E) 8 25, crosshair";

  window.addEventListener("message", function (event) {
    if (event.source !== window.parent) return;
    var data = event.data;
    if (!data || typeof data.type !== "string") return;

    if (data.type === "artifacto:mode") {
      commentMode = !!data.comment;
      document.documentElement.style.cursor = commentMode ? COMMENT_CURSOR : "";
    } else if (data.type === "artifacto:anchors") {
      anchors = Array.isArray(data.anchors) ? data.anchors : [];
      resolveAll(false);
      report();
    }
  });

  document.addEventListener("click", onClick, true);
  window.addEventListener("scroll", scheduleReport, true);
  window.addEventListener("resize", scheduleReport);

  // Content that only exists once images and deferred scripts have run can turn
  // a missed anchor into a hit.
  window.addEventListener("load", function () {
    if (!anchors.length) return;
    resolveAll(true);
    report();
  });

  // A mutation can do two things to an anchor: turn a miss into a hit (content
  // that renders late), and move one that was already placed. Both need an
  // answer, and both are throttled — the retry to 500ms, the re-measure to a
  // frame — so an artifact that animates its own DOM costs no more than a scroll.
  if (window.MutationObserver) {
    new MutationObserver(function () {
      scheduleRetry();
      scheduleReport();
    }).observe(document.documentElement, { childList: true, subtree: true, characterData: true });
  }
  send({ type: "artifacto:ready" });
})();
