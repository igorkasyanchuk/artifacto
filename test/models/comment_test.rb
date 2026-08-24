require "test_helper"

class CommentTest < ActiveSupport::TestCase
  setup do
    @artifact = Artifact.create_from_source!("<!DOCTYPE html><html><body><p>hi</p></body></html>")
  end

  test "the anchor and the body are both bounded" do
    comment = @artifact.comments.new(selector: "body", body: "ok")
    assert_predicate comment, :valid?

    comment.selector = "x" * (Comment::MAX_SELECTOR + 1)
    assert_not_predicate comment, :valid?

    comment.selector = "body"
    comment.quote = "x" * (Comment::MAX_QUOTE + 1)
    assert_not_predicate comment, :valid?
  end

  test "the JSON an agent reads back carries no reader identity" do
    comment = @artifact.comments.create!(selector: "body", body: "fix the axis", author_ip_hash: "abc")

    assert_equal %w[id selector quote body created_at], comment.as_json.keys.map(&:to_s)
  end
end
