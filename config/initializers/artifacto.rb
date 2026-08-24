Rails.application.configure do
  # Artifacts live on their own subdomain of a separate registrable domain, so a
  # cookie set on the app can never travel there and no two artifacts share an origin.
  config.x.content_host   = ENV.fetch("CONTENT_HOST", "usercontent.localhost")
  config.x.content_scheme = Rails.env.production? ? "https" : "http"
  config.x.content_port   = Rails.env.production? ? nil : ENV.fetch("PORT", 3000)

  # The app answers on whatever hostname the platform gives it, so no host is
  # hardcoded or matched anywhere. Only the *origin* has to be pinned — it ends up
  # in `frame-ancestors` and in the URLs the API returns, and both have to be exact.
  strict = Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?

  config.x.app_origin =
    ENV.fetch("APP_ORIGIN") do
      raise "APP_ORIGIN is required (e.g. https://your-app.example.com)" if strict
      "http://localhost:#{ENV.fetch('PORT', 3000)}"
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
