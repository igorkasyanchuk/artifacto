# Markdown artifacts are rendered by us, not by the uploader, so the result is
# trusted output: `unsafe: false` drops raw HTML at parse time and the sanitizer
# is the second line. That is why Markdown artifacts get a much stricter CSP.
module MarkdownDocument
  STYLE = <<~CSS.freeze
    /* Explicit colours on both sides: color-scheme alone leaves the text to the UA
       while the page keeps whatever the embedder painted, which reads as blank. */
    :root { color-scheme: light dark; --bg: #ffffff; --fg: #14161a; --soft: rgba(127,127,127,.14); }
    @media (prefers-color-scheme: dark) { :root { --bg: #0e1116; --fg: #e6e8eb; } }
    body { margin: 0 auto; padding: 2.5rem 1.25rem; max-width: 44rem; line-height: 1.65;
           background: var(--bg); color: var(--fg);
           font: 16px/1.65 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; }
    a { color: #2563eb; }
    @media (prefers-color-scheme: dark) { a { color: #6ea8fe; } }
    h1, h2, h3 { line-height: 1.25; margin-top: 2em; }
    pre { padding: 1rem; overflow-x: auto; border-radius: 6px; background: var(--soft); }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
    pre code { font-size: .85em; }
    table { border-collapse: collapse; width: 100%; overflow-x: auto; display: block; }
    th, td { border: 1px solid rgba(127,127,127,.35); padding: .4rem .6rem; text-align: left; }
    blockquote { margin-left: 0; padding-left: 1rem; border-left: 3px solid rgba(127,127,127,.4); }
    img { max-width: 100%; height: auto; }
  CSS

  def self.render(source, title: nil)
    body = Commonmarker.to_html(source, options: { render: { unsafe: false } })
    body = ActionController::Base.helpers.sanitize(body)
    heading = title.presence || "Artifact"

    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{ERB::Util.html_escape(heading)}</title>
      <style>#{STYLE}</style>
      </head>
      <body>
      #{body}
      </body>
      </html>
    HTML
  end
end
