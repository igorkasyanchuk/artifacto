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
end
