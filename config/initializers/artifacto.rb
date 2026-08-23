Rails.application.configure do
  config.x.app_host     = ENV.fetch("APP_HOST", "artifacto.localhost")
  config.x.content_host = ENV.fetch("CONTENT_HOST", "usercontent.localhost")

  # Artifacts live on their own subdomain of a separate registrable domain, so a
  # cookie set on the app can never travel there and no two artifacts share an origin.
  default_origin =
    if Rails.env.production?
      "https://#{config.x.app_host}"
    else
      "http://#{config.x.app_host}:#{ENV.fetch('PORT', 3000)}"
    end

  config.x.app_origin = ENV.fetch("APP_ORIGIN", default_origin)
  # Env override so a TLS-less staging box (sslip.io, plain HTTP) can
  # still build correct artifact URLs. Production must leave this at https.
  config.x.content_scheme = ENV.fetch("CONTENT_SCHEME") { Rails.env.production? ? "https" : "http" }
  config.x.content_port = Rails.env.production? ? nil : ENV.fetch("PORT", 3000)

  # Keys come from ENV so the repo stays safe to open-source. The development
  # fallbacks are throwaway values and must never reach production — deploy sets
  # all three as secrets.
  config.active_record.encryption.primary_key =
    ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY") { Rails.env.production? ? raise("AR_ENCRYPTION_PRIMARY_KEY is required") : "dev" * 8 }
  config.active_record.encryption.deterministic_key =
    ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY") { Rails.env.production? ? raise("AR_ENCRYPTION_DETERMINISTIC_KEY is required") : "det" * 8 }
  config.active_record.encryption.key_derivation_salt =
    ENV.fetch("AR_ENCRYPTION_SALT") { Rails.env.production? ? raise("AR_ENCRYPTION_SALT is required") : "salt" * 8 }
end
