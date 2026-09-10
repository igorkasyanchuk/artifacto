# Error tracking. The backend is Bugsink (https://bugsink.igorkasyanchuk.com), which
# speaks the Sentry protocol, so the Sentry SDKs work against it unchanged.
#
# No DSN, no client: development, tests and the asset build all run with Sentry
# uninitialized, and every Sentry.* call becomes a no-op. Set SENTRY_DSN locally
# to send events from a console.
return if ENV["SENTRY_DSN"].blank?

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]
  config.environment = Rails.env

  # Artifacts carry user content and creator IPs (encrypted at rest here — see
  # config/initializers/artifacto.rb), so nothing request-scoped goes out beyond
  # what an exception needs: no cookies, no headers, no request bodies.
  config.send_default_pii = false

  # Bugsink stores errors, not traces. Leaving the sample rates unset keeps the
  # SDK from sending transactions it would only drop on the other end.
end
