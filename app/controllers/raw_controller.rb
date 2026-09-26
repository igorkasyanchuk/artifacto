# Serves the artifact itself: from <slug>.CONTENT_HOST when there is a content
# zone, from /raw/<slug> when there is not. Everything here runs in a zone that
# hosts foreign JavaScript, so it sets no cookies and answers nothing but the
# artifact body.
class RawController < ActionController::Base
  # In single-origin mode the artifact is served from the app's own origin, so
  # allow-same-origin would hand uploaded JavaScript the app's storage and let
  # every artifact read every other one. Withholding it forces an opaque origin
  # instead, which is the isolation a second domain would have given. The cost is
  # that storage APIs stop working inside artifacts.
  #
  # Shared with the wrapper's <iframe sandbox>: the browser applies the
  # intersection of the two, so they must never drift apart.
  def self.sandbox_flags
    [ "allow-scripts", "allow-modals", ("allow-same-origin" if Rails.configuration.x.content_host) ].compact.join(" ")
  end

  def show
    # The body is fetched only once we know the answer is not a 304.
    artifact = Artifact.without_content.find_by(slug: params[:slug] || request.subdomains.first)
    return head :not_found if artifact.nil?
    return head :gone if artifact.expired?
    return head :unavailable_for_legal_reasons if artifact.blocked?
    return head :unauthorized if artifact.pin? && !pin_token_valid?(artifact)

    apply_artifact_headers(artifact)

    fresh_when(strong_etag: artifact.etag, last_modified: artifact.updated_at, public: !artifact.pin?)
    return if performed?

    Artifact.update_counters(artifact.id, view_count: 1)
    render body: Artifact.where(id: artifact.id).pick(:content)
  end

  def robots
    render plain: "User-agent: *\nDisallow: /\n", content_type: "text/plain"
  end

  def not_found = head :not_found

  private
    def apply_artifact_headers(artifact)
      # Framed by our own wrapper via frame-ancestors; the legacy header would veto it.
      response.headers.delete("X-Frame-Options")

      response.headers["Content-Type"] = "text/html; charset=utf-8"
      response.headers["Content-Encoding"] = "gzip"
      response.headers["Content-Disposition"] = "inline"
      response.headers["Content-Security-Policy"] = content_security_policy_for(artifact)
      response.headers["X-Content-Type-Options"] = "nosniff"
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      response.headers["Referrer-Policy"] = "no-referrer"
      response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
      response.headers["Cross-Origin-Resource-Policy"] = "same-site"
      response.headers["Permissions-Policy"] =
        "camera=(), microphone=(), geolocation=(), payment=(), usb=(), serial=()"
      response.headers["Cache-Control"] = cache_control_for(artifact)
    end

    def cache_control_for(artifact)
      return "private, no-store" if artifact.pin?

      seconds = Artifact.cache_seconds
      # max-age=0 rather than no-cache: Rails' own conditional-get handling
      # normalises no-cache away here, and zero seconds already forces the
      # revalidation we want — which the ETag then answers with a 304.
      return "public, max-age=0" if seconds <= 0

      # Capped at the freshness window: serving a stale copy for longer than the
      # artifact was ever fresh would undo a deliberately short cache_seconds.
      "public, max-age=#{seconds}, stale-while-revalidate=#{[ seconds, 60 ].min}"
    end

    def content_security_policy_for(artifact)
      # Markdown output is ours, so only our injected hook may run. Uploaded HTML
      # needs inline scripts to work at all; the origin boundary is what contains it.
      script = artifact.format == "markdown" ? AgentInjector.csp_hash : "'unsafe-inline' 'unsafe-eval'"

      [
        "default-src 'none'",
        "script-src #{script}",
        "style-src 'unsafe-inline'",
        "img-src data: blob:",
        "font-src data:",
        "media-src data: blob:",
        # No exfiltration path unless the uploader explicitly asked for one.
        "connect-src #{artifact.allow_network? ? 'https:' : "'none'"}",
        "form-action 'none'",
        "base-uri 'none'",
        "frame-ancestors #{[ "'self'", Rails.configuration.x.app_origin ].compact.join(' ')}",
        # No allow-downloads: an artifact cannot hand the viewer a file.
        # No allow-popups: window.open would otherwise open an arbitrary external
        # page in a new tab, which is the one way left to redirect a viewer.
        # Both mean an artifact cannot link out at all — which is what
        # "self-contained" was supposed to mean anyway.
        "sandbox #{self.class.sandbox_flags}"
      ].join("; ")
    end

    # The PIN itself is checked on the app host. Here we only accept the
    # short-lived signed token it hands out, so this zone stays cookie-free.
    def pin_token_valid?(artifact)
      Rails.application.message_verifier(:artifact_pin).verified(params[:t].to_s) == artifact.slug
    end
end
