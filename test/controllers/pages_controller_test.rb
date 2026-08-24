require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "the skill file downloads with this deployment's URL baked in" do
    get "/skill"

    assert_response :success
    assert_match %r{text/markdown}, response.headers["Content-Type"]
    assert_match %r{filename="SKILL\.md"}, response.headers["Content-Disposition"]

    # The shipped copy points at artifacto.app; a downloaded copy that still did
    # would send every agent using it to somebody else's server.
    refute_includes response.body, "artifacto.app"
    base = root_url.chomp("/")
    assert_includes response.body, "${ARTIFACTO_URL:-#{base}}/api/v1/artifacts"
    assert_includes response.body, "#{base}/a/#{PagesController::SKILL_SAMPLE_SLUG}"
  end

  test "the landing page offers the skill" do
    get "/"

    assert_response :success
    assert_select "a[href=?]", "/skill"
  end
end
