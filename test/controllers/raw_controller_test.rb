require "test_helper"

class RawControllerTest < ActionDispatch::IntegrationTest
  HTML = "<!DOCTYPE html><html><body><p>artifact</p></body></html>".freeze

  setup { @artifact = Artifact.create_from_source!(HTML, title: "T") }

  test "serves the artifact gzipped from its own subdomain" do
    get_artifact @artifact

    assert_response :success
    assert_equal "gzip", response.headers["Content-Encoding"]
    assert_equal "text/html; charset=utf-8", response.headers["Content-Type"]
    assert_includes Artifact.gunzip(response.body), "<p>artifact</p>"
  end

  test "isolation headers are present" do
    get_artifact @artifact
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "connect-src 'none'"
    assert_includes csp, "form-action 'none'"
    assert_includes csp, "default-src 'none'"
    assert_includes csp, "base-uri 'none'"
    assert_includes csp, "frame-ancestors 'self' #{Rails.configuration.x.app_origin}"
    assert_includes csp, "sandbox allow-scripts"
    assert_not_includes csp, "allow-top-navigation"
    assert_not_includes csp, "allow-downloads"
    assert_not_includes csp, "allow-popups"
    assert_nil response.headers["X-Frame-Options"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "noindex, nofollow", response.headers["X-Robots-Tag"]
  end

  test "allow_network opens connect-src and nothing else" do
    @artifact.update!(allow_network: true)
    get_artifact @artifact
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "connect-src https:"
    assert_includes csp, "form-action 'none'"
  end

  test "markdown artifacts may run only our injected hook" do
    markdown = Artifact.create_from_source!("# hi", format: "markdown")
    get_artifact markdown
    csp = response.headers["Content-Security-Policy"]

    assert_includes csp, "script-src #{AgentInjector.csp_hash}"
    assert_not_includes csp, "unsafe-eval"
  end

  test "expired is gone, blocked is 451, unknown is 404" do
    @artifact.update_column(:expires_at, 1.hour.ago)
    get_artifact @artifact
    assert_response :gone

    @artifact.update_columns(expires_at: 1.day.from_now, blocked_at: Time.current)
    get_artifact @artifact
    assert_response :unavailable_for_legal_reasons

    host! "#{'z' * 22}.#{Rails.configuration.x.content_host}"
    get "/"
    assert_response :not_found
  end

  test "cache lifetime follows ARTIFACT_CACHE_SECONDS" do
    get_artifact @artifact
    assert_includes response.headers["Cache-Control"], "max-age=300"
    assert_includes response.headers["Cache-Control"], "stale-while-revalidate=60"

    with_cache_seconds("30") do
      get_artifact @artifact
      assert_includes response.headers["Cache-Control"], "max-age=30"
      # Never stale for longer than it was fresh.
      assert_includes response.headers["Cache-Control"], "stale-while-revalidate=30"
    end

    with_cache_seconds("0") do
      get_artifact @artifact
      assert_includes response.headers["Cache-Control"], "max-age=0"
      assert_not_includes response.headers["Cache-Control"], "stale-while-revalidate"
    end
  end

  test "a pinned artifact needs a signed token, not a cookie" do
    @artifact.update!(pin: "123456")

    get_artifact @artifact
    assert_response :unauthorized

    token = Rails.application.message_verifier(:artifact_pin).generate(@artifact.slug, expires_in: 10.minutes)
    get_artifact @artifact, params: { t: token }
    assert_response :success
    assert_equal "private, no-store", response.headers["Cache-Control"]

    other = Rails.application.message_verifier(:artifact_pin).generate("someone-else", expires_in: 10.minutes)
    get_artifact @artifact, params: { t: other }
    assert_response :unauthorized
  end

  test "the content host answers nothing but the artifact" do
    host! "#{@artifact.slug}.#{Rails.configuration.x.content_host}"

    get "/api/v1/artifacts/#{@artifact.slug}"
    assert_response :not_found

    get "/robots.txt"
    assert_includes response.body, "Disallow: /"
  end

  test "a repeat visit is answered from cache without a second view count" do
    get_artifact @artifact
    etag = response.headers["ETag"]

    get_artifact @artifact, headers: { "If-None-Match" => etag }
    assert_response :not_modified
    assert_equal 1, @artifact.reload.view_count
  end

  private
    def get_artifact(artifact, params: {}, headers: {})
      host! "#{artifact.slug}.#{Rails.configuration.x.content_host}"
      get "/", params: params, headers: headers
    end

    def with_cache_seconds(value)
      previous = ENV["ARTIFACT_CACHE_SECONDS"]
      ENV["ARTIFACT_CACHE_SECONDS"] = value
      yield
    ensure
      ENV["ARTIFACT_CACHE_SECONDS"] = previous
    end
end
