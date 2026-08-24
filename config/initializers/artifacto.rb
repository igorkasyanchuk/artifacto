Rails.application.configure do
  # Two-zone mode: set CONTENT_HOST to a *different registrable domain* and each
  # artifact is served from its own subdomain of it, so no artifact shares an
  # origin with the app or with another artifact. This is the design the security
  # model assumes, and APP_ORIGIN is required with it.
  #
  # Leave CONTENT_HOST unset and the app runs in single-origin mode instead:
  # artifacts are served from /raw/<slug> on whatever host the request arrived
  # on, no second domain and no configuration at all. Cheaper to deploy, weaker
  # isolation — RawController drops allow-same-origin there to claw back most of
  # it. See the README before running that in anger.
  config.x.content_host   = ENV["CONTENT_HOST"].presence
  config.x.content_scheme = Rails.env.production? ? "https" : "http"
  config.x.content_port   = Rails.env.production? ? nil : ENV.fetch("PORT", 3000)

  # No host is hardcoded or matched anywhere, so the app answers on whatever
  # domain it is deployed under. APP_ORIGIN only pins the origin used in
  # frame-ancestors and in the artifact's postMessage target, both of which have
  # to be exact — and both of which are only needed across a zone boundary.
  config.x.app_origin = ENV["APP_ORIGIN"].presence

  strict = Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?

  if strict && config.x.content_host && config.x.app_origin.nil?
    raise "APP_ORIGIN is required when CONTENT_HOST is set (e.g. https://your-app.example.com)"
  end

  # Keys come from ENV so the repo stays safe to open-source. The fallbacks are
  # throwaway values for development, tests and the asset build — never production.
  config.active_record.encryption.primary_key =
    ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY") { raise("AR_ENCRYPTION_PRIMARY_KEY is required") if strict; "dev" * 8 }
  config.active_record.encryption.deterministic_key =
    ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY") { raise("AR_ENCRYPTION_DETERMINISTIC_KEY is required") if strict; "det" * 8 }
  config.active_record.encryption.key_derivation_salt =
    ENV.fetch("AR_ENCRYPTION_SALT") { raise("AR_ENCRYPTION_SALT is required") if strict; "salt" * 8 }
end
