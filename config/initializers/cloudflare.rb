# Behind Cloudflare every request reaches Rails from a Cloudflare edge address,
# and Rails trusts only private ranges — so request.remote_ip was Cloudflare's.
# Every per-IP rate limit was then shared by strangers on the same edge, and
# every IP hash (bans, creator_ip) named Cloudflare instead of a person.
#
# BEHIND_CLOUDFLARE=true trusts Cloudflare's ranges and takes the visitor from
# CF-Connecting-IP. The proxy between Cloudflare and us (Traefik, kamal-proxy)
# may drop Cloudflare's own X-Forwarded-For, which is why the header is read
# directly rather than relying on the forwarded chain.
class CloudflareClientIp
  # ponytail: copied from https://www.cloudflare.com/ips/ on 2026-09-26. They
  # change rarely; re-copy if Cloudflare announces new ranges.
  RANGES = %w[
    173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18
    108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17
    162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
    2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32
    2a06:98c0::/29 2c0f:f248::/32
  ].map { |range| IPAddr.new(range) }.freeze

  def initialize(app) = @app = app

  # Prepended to X-Forwarded-For, never substituted: RemoteIp walks that list
  # from the right and stops at the first untrusted hop, so this entry is only
  # reached through a Cloudflare address. A request that skipped Cloudflare —
  # straight at the origin IP — stops at its own address, whatever it forged here.
  def call(env)
    if (visitor = env["HTTP_CF_CONNECTING_IP"].presence)
      env["HTTP_X_FORWARDED_FOR"] = [ visitor, env["HTTP_X_FORWARDED_FOR"].presence ].compact.join(", ")
    end

    @app.call(env)
  end
end

if ENV["BEHIND_CLOUDFLARE"] == "true"
  Rails.application.configure do
    config.action_dispatch.trusted_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + CloudflareClientIp::RANGES
    config.middleware.insert_before ActionDispatch::RemoteIp, CloudflareClientIp
  end
end
