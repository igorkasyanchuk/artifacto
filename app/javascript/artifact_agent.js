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

  // A PUT replaces the whole body, so an nth-of-type chain written against the
  // old markup will usually miss. The quote is the fallback: find the deepest
  // element still containing that text. Document order puts children after
  // their parents, so the last match is the deepest one.
  function findByQuote(quote) {
    var needle = norm(quote).slice(0, 60);
    if (!needle) return null;
    var all = document.body ? document.body.querySelectorAll("*") : [];
    var found = null;
    for (var i = 0; i < all.length; i++) {
      if (norm(all[i].textContent).indexOf(needle) !== -1) found = all[i];
    }
    return found;
  }

  function resolve(anchor) {
    var el = null;
    try { el = document.querySelector(anchor.selector); } catch (e) { el = null; }
    if (el) return { el: el, moved: false };

    el = findByQuote(anchor.quote);
    return el ? { el: el, moved: true } : null;
  }

  // ponytail: re-resolved on every report rather than cached, because an
  // interactive artifact can rewrite its own DOM. Cache by selector if a huge
  // artifact ever makes this show up in a profile.
  function report() {
    var positions = [];
    for (var i = 0; i < anchors.length; i++) {
      var hit = resolve(anchors[i]);
      if (!hit) {
        positions.push({ key: anchors[i].key, found: false });
        continue;
      }
      var rect = hit.el.getBoundingClientRect();
      positions.push({
        key: anchors[i].key,
        found: true,
        moved: hit.moved,
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
      report();
    }
  });

  document.addEventListener("click", onClick, true);
  window.addEventListener("scroll", scheduleReport, true);
  window.addEventListener("resize", scheduleReport);
  send({ type: "artifacto:ready" });
})();
