require "test_helper"

# With CONTENT_HOST unset there is no second domain, so artifacts are served
# from a path on whatever host the request arrived on. That trades away the
# origin boundary, and the sandbox has to make up for it.
class SingleOriginTest < ActionDispatch::IntegrationTest
  HTML = "<!DOCTYPE html><html><body><p>same origin</p></body></html>".freeze

  setup do
    @content_host = Rails.configuration.x.content_host
    @app_origin = Rails.configuration.x.app_origin
    Rails.configuration.x.content_host = nil
    Rails.configuration.x.app_origin = nil
    Rails.application.reload_routes!

    @artifact = Artifact.create_from_source!(HTML, title: "Same origin")
  end

  teardown do
    Rails.configuration.x.content_host = @content_host
    Rails.configuration.x.app_origin = @app_origin
    Rails.application.reload_routes!
  end

  test "the artifact is served from a path on the requesting host" do
    get "/raw/#{@artifact.slug}"

    assert_response :success
    assert_equal HTML, Artifact.gunzip(response.body).sub(AgentInjector::BLOCK, "")
  end

  test "the sandbox withholds allow-same-origin, so the artifact gets an opaque origin" do
    get "/raw/#{@artifact.slug}"

    csp = response.headers["Content-Security-Policy"]
    assert_includes csp, "sandbox allow-scripts allow-modals"
    refute_includes csp, "allow-same-origin"
    assert_includes csp, "frame-ancestors 'self'"
  end

  test "the wrapper frames the artifact by path and answers on any host" do
    host! "some-random-name.example.net"
    get "/a/#{@artifact.slug}"

    assert_response :success
    assert_includes response.body, "/raw/#{@artifact.slug}"
  end
end
