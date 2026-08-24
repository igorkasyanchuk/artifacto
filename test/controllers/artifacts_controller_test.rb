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
