require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "the skill file downloads with this deployment's URL baked in" do
    get "/skill"

    assert_response :success
    assert_match %r{text/markdown}, response.headers["Content-Type"]
    assert_match %r{filename="SKILL\.md"}, response.headers["Content-Disposition"]

    # The shipped copy points at the public instance; a downloaded copy that
    # still did would send every agent using it to somebody else's server.
    refute_includes response.body, "artifacto.igorkasyanchuk.com"
    base = root_url.chomp("/")
    assert_includes response.body, "${ARTIFACTO_URL:-#{base}}/api/v1/artifacts"
    assert_includes response.body, "#{base}/a/#{PagesController::SKILL_SAMPLE_SLUG}"
  end

  test "the landing page carries an install command built from the requesting host" do
    host! "some-random-name.example.net"
    get "/"

    assert_response :success
    assert_select "a[href=?]", "/skill"
    # The command is copied verbatim, so a placeholder host would send the agent
    # to the wrong server without anyone noticing.
    assert_select "[data-clipboard-target=source]",
      text: /curl -sf http:\/\/some-random-name\.example\.net\/skill/
  end

  test "the terms page names the abuse contact when one is configured" do
    ENV["ABUSE_EMAIL"] = "abuse@example.org"
    get "/terms"

    assert_response :success
    assert_select "a[href='mailto:abuse@example.org']"
  ensure
    ENV.delete("ABUSE_EMAIL")
  end

  test "the terms page leaves the contact out entirely without one" do
    get "/terms"

    assert_response :success
    assert_select "#contact", false
    assert_select "a[href^='mailto:']", false
    assert_no_match(/write to|address above/, response.body)
    assert_match "Report", response.body
  end

  test "analytics loads on the public pages only, and only when configured" do
    x = Rails.configuration.x
    get "/"
    assert_select "script[data-website-id]", false
    assert_no_match "umami", response.headers["Content-Security-Policy"]

    x.umami_script_url = "https://umami.example.org/script.js"
    x.umami_website_id = "site-1"
    x.umami_origin = "https://umami.example.org"

    get "/"
    assert_select "script[src='https://umami.example.org/script.js'][data-website-id='site-1'][data-turbo-track=reload][nonce]"
    assert_match %r{script-src 'self' https://umami\.example\.org}, response.headers["Content-Security-Policy"]
    assert_match %r{connect-src 'self' https://umami\.example\.org}, response.headers["Content-Security-Policy"]

    get "/terms"
    assert_select "script[data-website-id='site-1']"
    assert_match "Umami", response.body

    # The sign-in page shares the layout; it must not load the script or widen its policy.
    get new_user_session_path
    assert_select "script[data-website-id]", false
    assert_no_match "umami", response.headers["Content-Security-Policy"]
  ensure
    x.umami_script_url = x.umami_website_id = x.umami_origin = nil
  end

  test "the analytics URL is checked once, at boot" do
    initializer = Rails.root.join("config/initializers/artifacto.rb")
    ENV["UMAMI_WEBSITE_ID"] = "site-1"

    ENV["UMAMI_SCRIPT_URL"] = " https://umami.example.org:8443/script.js "
    load initializer
    assert_equal "https://umami.example.org:8443", Rails.configuration.x.umami_origin

    ENV["UMAMI_SCRIPT_URL"] = "umami.example.org/script.js"
    assert_raises(RuntimeError) { load initializer }
  ensure
    ENV.delete("UMAMI_SCRIPT_URL")
    ENV.delete("UMAMI_WEBSITE_ID")
    load initializer
  end

  test "robots keep crawlers off artifacts in both zone layouts" do
    get "/robots.txt"

    assert_includes response.body, "Disallow: /a/"
    assert_includes response.body, "Disallow: /raw/"
  end
end
