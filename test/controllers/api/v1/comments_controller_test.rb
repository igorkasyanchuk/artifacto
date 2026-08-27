require "test_helper"

class Api::V1::CommentsControllerTest < ActionDispatch::IntegrationTest
  HTML = "<!DOCTYPE html><html><body><p>anchor me</p></body></html>".freeze

  setup do
    @artifact = Artifact.create_from_source!(HTML, title: "Commented")
    @token = @artifact.edit_token
  end

  def post_comment(**params)
    post "/api/v1/artifacts/#{@artifact.slug}/comments",
         params: { selector: "body > p", quote: "anchor me", body: "needs a chart" }.merge(params)
  end

  test "anyone holding the link can comment, and anyone can read them back" do
    assert_difference "Comment.count", 1 do
      post_comment
    end
    assert_response :created

    get "/api/v1/artifacts/#{@artifact.slug}/comments"
    assert_response :success

    comment = response.parsed_body["comments"].sole
    assert_equal "needs a chart", comment["body"]
    assert_equal "body > p", comment["selector"]
    assert_equal "anchor me", comment["quote"]
  end

  test "an author name is optional, kept when given and truncated when long" do
    post_comment
    assert_nil Comment.sole.author
    assert_nil response.parsed_body["author"]

    post_comment(author: "  Dana  ")
    assert_equal "Dana", Comment.order(:id).last.author

    post_comment(author: "x" * (Comment::MAX_AUTHOR + 50))
    assert_response :created
    assert_equal Comment::MAX_AUTHOR, Comment.order(:id).last.author.length
  end

  test "the IP is only ever stored hashed" do
    post_comment
    assert_equal Artifact.hash_ip("127.0.0.1"), Comment.sole.author_ip_hash
    assert_not_includes response.body, "author_ip_hash"
  end

  test "an empty body is rejected and an over-long one is truncated" do
    assert_no_difference "Comment.count" do
      post_comment(body: "   ")
    end
    assert_response :unprocessable_entity

    post_comment(body: "x" * (Comment::MAX_BODY + 100))
    assert_response :created
    assert_equal Comment::MAX_BODY, Comment.sole.body.length
  end

  test "comments follow the artifact's own availability" do
    post "/api/v1/artifacts/nope/comments", params: { selector: "body", body: "hi" }
    assert_response :not_found

    @artifact.update!(blocked_at: Time.current)
    get "/api/v1/artifacts/#{@artifact.slug}/comments"
    assert_response :unavailable_for_legal_reasons
  end

  test "deleting a comment needs the artifact's edit token" do
    post_comment
    comment = Comment.sole

    delete "/api/v1/artifacts/#{@artifact.slug}/comments/#{comment.id}"
    assert_response :unauthorized

    assert_difference "Comment.count", -1 do
      delete "/api/v1/artifacts/#{@artifact.slug}/comments/#{comment.id}",
             headers: { "Authorization" => "Bearer #{@token}" }
    end
    assert_response :no_content
  end

  test "an edit that breaks the selector leaves the quote to re-anchor on" do
    post_comment
    put "/api/v1/artifacts/#{@artifact.slug}",
        params: { source: "<!DOCTYPE html><html><body><div><p>anchor me</p></div></body></html>" },
        headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success

    comment = Comment.sole
    assert_equal "body > p", comment.selector, "the stale selector is kept as the first guess"
    assert_equal "anchor me", comment.quote, "and the quote survives, which is what the frame re-anchors on"
  end

  test "a PIN gates the comments too, since a quote is text out of the locked page" do
    @artifact.update!(pin: "1234")

    post "/api/v1/artifacts/#{@artifact.slug}/comments", params: { selector: "body > p", body: "leak" }
    assert_response :unauthorized

    get "/api/v1/artifacts/#{@artifact.slug}/comments"
    assert_response :unauthorized

    token = Rails.application.message_verifier(:artifact_pin).generate(@artifact.slug, expires_in: 10.minutes)
    post "/api/v1/artifacts/#{@artifact.slug}/comments",
         params: { selector: "body > p", quote: "anchor me", body: "allowed", t: token }
    assert_response :created

    get "/api/v1/artifacts/#{@artifact.slug}/comments", params: { t: token }
    assert_response :success
  end

  test "the edit token outranks the PIN, so the publishing agent still reads its feedback" do
    @artifact.comments.create!(selector: "body > p", quote: "anchor me", body: "needs a chart")
    @artifact.update!(pin: "1234")

    get "/api/v1/artifacts/#{@artifact.slug}/comments",
        headers: { "Authorization" => "Bearer #{@token}" }
    assert_response :success
    assert_equal "needs a chart", response.parsed_body["comments"].sole["body"]
  end

  test "a comment id that does not exist answers in JSON, not an HTML error page" do
    delete "/api/v1/artifacts/#{@artifact.slug}/comments/999999",
           headers: { "Authorization" => "Bearer #{@token}" }

    assert_response :not_found
    assert_equal "application/json", response.media_type
    assert_equal "not found", response.parsed_body["error"]
  end

  test "comments go away with the artifact" do
    post_comment
    assert_difference "Comment.count", -1 do
      @artifact.destroy!
    end
  end

  test "an artifact cannot be used as free storage" do
    Comment::MAX_PER_ARTIFACT.times do |i|
      @artifact.comments.create!(selector: "body", body: "filler #{i}")
    end

    assert_no_difference "Comment.count" do
      post_comment
    end
    assert_response :too_many_requests
  end
end
