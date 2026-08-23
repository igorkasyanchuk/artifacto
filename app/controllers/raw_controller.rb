# Serves the artifact itself, on <slug>.CONTENT_HOST. Everything here runs in a
# zone that hosts foreign JavaScript, so it sets no cookies and answers nothing
# but the artifact body.
class RawController < ActionController::Base
  def show
    artifact = Artifact.find_by(slug: request.subdomains.first)
    return head :not_found if artifact.nil?
    return head :gone if artifact.expired?
    return head :unavailable_for_legal_reasons if artifact.blocked?
    return head :unauthorized if artifact.pin? && !pin_token_valid?(artifact)

    apply_artifact_headers(artifact)

    fresh_when(strong_etag: artifact.etag, last_modified: artifact.updated_at, public: !artifact.pin?)
    return if performed?

    Artifact.update_counters(artifact.id, view_count: 1)
    render body: artifact.content
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
      response.headers["Cache-Control"] =
        artifact.pin? ? "private, no-store" : "public, max-age=300, stale-while-revalidate=60"
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
        "frame-ancestors 'self' #{Rails.configuration.x.app_origin}",
        # No allow-downloads: an artifact cannot hand the viewer a file.
        # No allow-popups: window.open would otherwise open an arbitrary external
        # page in a new tab, which is the one way left to redirect a viewer.
        # Both mean an artifact cannot link out at all — which is what
        # "self-contained" was supposed to mean anyway.
        "sandbox allow-scripts allow-same-origin allow-modals"
      ].join("; ")
    end

    # The PIN itself is checked on the app host. Here we only accept the
    # short-lived signed token it hands out, so this zone stays cookie-free.
    def pin_token_valid?(artifact)
      Rails.application.message_verifier(:artifact_pin).verified(params[:t].to_s) == artifact.slug
    end
end
