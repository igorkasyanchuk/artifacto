// Injected into every served artifact. Phase 1 only opens the channel; the
// comment UI on the wrapper page is built on top of it in phase 2.
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

  window.addEventListener("message", function (event) {
    if (event.source !== window.parent) return;
    var data = event.data;
    if (!data || data.type !== "artifacto:mode") return;
    commentMode = !!data.comment;
    document.documentElement.style.cursor = commentMode ? "crosshair" : "";
  });

  document.addEventListener("click", onClick, true);
  send({ type: "artifacto:ready" });
})();
