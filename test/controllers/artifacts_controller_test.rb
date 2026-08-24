require "test_helper"

class ArtifactsControllerTest < ActionDispatch::IntegrationTest
  HTML = "<!DOCTYPE html><html><body><p>wrapped</p></body></html>".freeze

  setup do
    @artifact = Artifact.create_from_source!(HTML, title: "Wrapped")
  end

  test "the wrapper frames the content origin and never inlines the artifact" do
    get "/a/#{@artifact.slug}"

    assert_response :success
    assert_includes response.body, @artifact.content_url
    assert_not_includes response.body, "<p>wrapped</p>"
  end

  test "the wrapper carries the comment overlay and the slug its fetch needs" do
    get "/a/#{@artifact.slug}"

    assert_select "[data-wrapper-slug-value=?]", @artifact.slug
    assert_select "[data-wrapper-target=overlay]"
    assert_select "[data-action='wrapper#toggle']"
  end

  test "a locked artifact offers nothing to comment on until it is unlocked" do
    @artifact.update!(pin: "1234")

    get "/a/#{@artifact.slug}"
    assert_select "[data-wrapper-target=overlay]", false
    assert_select "[data-action='wrapper#toggle']", false
  end

  test "each render of an unlocked artifact hands out a fresh token" do
    @artifact.update!(pin: "1234")
    verifier = Rails.application.message_verifier(:artifact_pin)

    post "/a/#{@artifact.slug}/unlock", params: { pin: "1234" }
    arrived_with = request.query_parameters["k"] || response.location[/k=([^&]+)/, 1]
    follow_redirect!

    handed_out = response.body[/data-wrapper-token-value="([^"]+)"/, 1]
    assert_equal @artifact.slug, verifier.verified(CGI.unescape(handed_out))
    assert_not_equal CGI.unescape(arrived_with.to_s), handed_out,
      "the overlay holds this for as long as the page stays open, so it must not inherit the arriving token's remaining life"
  end

  test "a pinned artifact asks for the PIN before framing anything" do
    @artifact.update!(pin: "1234")

    get "/a/#{@artifact.slug}"
    assert_response :success
    assert_not_includes response.body, "<iframe"

    post "/a/#{@artifact.slug}/unlock", params: { pin: "nope" }
    assert_response :unauthorized

    post "/a/#{@artifact.slug}/unlock", params: { pin: "1234" }
    assert_response :redirect
    follow_redirect!
    assert_includes response.body, "<iframe"
  end

  test "reporting an artifact files it for review" do
    assert_difference "AbuseReport.count", 1 do
      post "/a/#{@artifact.slug}/report", params: { reason: "phishing" }
    end

    assert_redirected_to "/a/#{@artifact.slug}"
  end
end
