require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # TLS terminates at the proxy in front of this app (Coolify's Traefik, kamal-proxy,
  # Cloudflare), which then speaks plain HTTP to the container. Without assume_ssl
  # Rails would see http, mark cookies insecure, and force_ssl would redirect in a
  # loop. Set FORCE_SSL=false only if the app is genuinely served over http.
  if ENV.fetch("FORCE_SSL", "true") == "true"
    config.assume_ssl = true
    config.force_ssl = true

    # The health check is requested over http from inside the network, so it must
    # answer 200 rather than a redirect or the platform calls the deploy dead.
    config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
  end

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!).
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Rails.cache is where ActionController::RateLimiting keeps its counters, so it
  # has to outlive a deploy and be shared by every process. The default file
  # store is neither. Redis is already here for Sidekiq.
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    namespace: "artifacto:cache",
    error_handler: ->(method:, returning:, exception:) {
      # A cache outage must not take the whole app down with it. Rate limiting
      # fails open here, which is the same thing the file store did on a fresh
      # container, and Cloudflare's rule is the real backstop anyway.
      Rails.logger.error("Rails.cache #{method} failed: #{exception.class}: #{exception.message}")
    }
  }

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :sidekiq

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Set host to be used by links generated in mailer templates.
  # Read from ENV, not config.x.app_origin: this file is evaluated before initializers.
  config.action_mailer.default_url_options = { host: URI(ENV.fetch("APP_ORIGIN", "http://localhost")).host }

  # Specify outgoing SMTP server. Remember to add smtp/* credentials via bin/rails credentials:edit.
  # config.action_mailer.smtp_settings = {
  #   user_name: Rails.application.credentials.dig(:smtp, :user_name),
  #   password: Rails.application.credentials.dig(:smtp, :password),
  #   address: "smtp.example.com",
  #   port: 587,
  #   authentication: :plain
  # }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # No host allowlist on purpose: the app answers on whatever hostname the
  # platform hands it, and every artifact needs its own `*.CONTENT_HOST`
  # subdomain to resolve here too. Routing, not Host, decides which zone a
  # request lands in — see config/routes.rb.
end
