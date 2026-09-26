require "test_helper"

class CloudflareClientIpTest < ActiveSupport::TestCase
  VISITOR = "198.51.100.7".freeze
  EDGE = "173.245.48.1".freeze      # inside Cloudflare's ranges
  PROXY = "10.0.1.5".freeze         # Traefik on the Docker network

  # The stack as production builds it with BEHIND_CLOUDFLARE=true.
  def remote_ip(headers)
    app = ->(env) { [ 200, {}, [ ActionDispatch::Request.new(env).remote_ip ] ] }
    proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES + CloudflareClientIp::RANGES
    stack = CloudflareClientIp.new(ActionDispatch::RemoteIp.new(app, true, proxies))

    stack.call(Rack::MockRequest.env_for("/", { "REMOTE_ADDR" => PROXY }.merge(headers)))[2].first
  end

  test "reads the visitor when the proxy dropped Cloudflare's forwarded chain" do
    assert_equal VISITOR, remote_ip("HTTP_X_FORWARDED_FOR" => EDGE, "HTTP_CF_CONNECTING_IP" => VISITOR)
  end

  test "reads the visitor when the proxy kept it" do
    assert_equal VISITOR, remote_ip("HTTP_X_FORWARDED_FOR" => "#{VISITOR}, #{EDGE}", "HTTP_CF_CONNECTING_IP" => VISITOR)
  end

  test "a request that skipped Cloudflare cannot forge its way to another address" do
    attacker = "203.0.113.9"

    assert_equal attacker, remote_ip("HTTP_X_FORWARDED_FOR" => attacker, "HTTP_CF_CONNECTING_IP" => VISITOR)
  end
end
