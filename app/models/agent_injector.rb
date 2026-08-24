require "base64"

# Wraps the artifact-side comment hook (app/javascript/artifact_agent.js) and
# splices it into every stored artifact. Injecting at write time keeps serving a
# straight byte dump; the trade-off is that artifacts created before a VERSION
# bump keep the old script until they are updated or expire (<= 30 days).
module AgentInjector
  VERSION = 2
  OPEN_MARKER = "<!--artifacto:agent-->"
  CLOSE_MARKER = "<!--/artifacto:agent-->"
  BLOCK = /#{Regexp.escape(OPEN_MARKER)}.*?#{Regexp.escape(CLOSE_MARKER)}\n?/m

  class << self
    def script
      @script ||= Rails.root.join("app/javascript/artifact_agent.js").read
        .sub("__PARENT_ORIGIN__", Rails.configuration.x.app_origin || "*")
    end

    # CSP source expression, so Markdown artifacts can run this script and
    # nothing else. A hash, not a nonce: a nonce would have to be unique per
    # response and that makes the artifact uncacheable on the CDN.
    def csp_hash
      @csp_hash ||= "'sha256-#{Base64.strict_encode64(Digest::SHA256.digest(script))}'"
    end

    def block
      @block ||= "#{OPEN_MARKER}<script>#{script}</script>#{CLOSE_MARKER}"
    end

    def inject(html)
      return html if html.include?(OPEN_MARKER)

      index = html.rindex(%r{</body>}i)
      index ? html.dup.insert(index, block) : html + block
    end

    def strip(html) = html.gsub(BLOCK, "")
  end
end
