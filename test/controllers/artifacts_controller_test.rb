require "test_helper"

class ArtifactsControllerTest < ActionDispatch::IntegrationTest
  HTML = "<!DOCTYPE html><html><body><p>wrapped</p></body></html>".freeze

  setup do
    @artifact = Artifact.create_from_source!(HTML, title: "Wrapped")
  end

  test "the wrapper page runs its own layout, with no Turbo on it" do
    get "/a/#{@artifact.slug}"

    assert_response :success
    # Its own entry point and stylesheet...
    assert_match %r{artifact[-.][\w.-]*\.js}, response.body
    assert_match %r{artifact[-.][\w.-]*\.css}, response.body
    # ...and nothing that runs or fetches Turbo next to a frame of foreign
    # JavaScript. The importmap manifest still names every pin — naming a module
    # is not importing it — so the assertions are about the entry point and the
    # preload list, which are what actually pull bytes.
    assert_match %r{<script type="module"[^>]*>import "artifact"</script>}, response.body
    assert_no_match %r{import "@hotwired/turbo-rails"}, response.body
    assert_no_match %r{modulepreload[^>]*turbo}, response.body
  end

  test "the landing page still gets the full application layout" do
    get "/"

    assert_response :success
    assert_match %r{application[-.][\w.-]*\.js}, response.body
    assert_not_includes response.body, "artifact.css"
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

    # The viewer renders its own flash inside the .viewer column; the layout
    # must not add a second copy above it.
    follow_redirect!
    assert_select ".flash", count: 1
  end
end
