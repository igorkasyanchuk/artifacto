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
    send({
      type: "artifacto:anchor",
      selector: cssPath(el),
      quote: (el.textContent || "").trim().slice(0, 200),
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

  function says(el, needle) {
    return !needle || norm(el.textContent).indexOf(needle) !== -1;
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
      if (norm(all[i].textContent).indexOf(needle) !== -1) found = all[i];
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
      if (!onlyMissing || !anchors[i].el) resolve(anchors[i]);
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

  var pending = false;

  function scheduleReport() {
    if (pending || !anchors.length) return;
    pending = true;
    window.requestAnimationFrame(function () {
      pending = false;
      report();
    });
  }

  window.addEventListener("message", function (event) {
    if (event.source !== window.parent) return;
    var data = event.data;
    if (!data || typeof data.type !== "string") return;

    if (data.type === "artifacto:mode") {
      commentMode = !!data.comment;
      document.documentElement.style.cursor = commentMode ? "crosshair" : "";
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
  // a missed anchor into a hit. Worth exactly one retry, for the missed ones.
  window.addEventListener("load", function () {
    if (!anchors.length) return;
    resolveAll(true);
    report();
  });
  send({ type: "artifacto:ready" });
})();
