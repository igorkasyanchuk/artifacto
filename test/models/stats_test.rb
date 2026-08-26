require "test_helper"

class StatsTest < ActiveSupport::TestCase
  test "counts artifacts by state and fills quiet days with zero" do
    live = Artifact.create!(slug: Artifact.generate_slug, content: "<p>hi</p>", byte_size: 9,
                            sha256: Digest::SHA256.hexdigest("hi"), edit_token_digest: "x",
                            expires_at: 3.days.from_now, user: users(:member))
    Artifact.create!(slug: Artifact.generate_slug, content: "<p>no</p>", byte_size: 9,
                     sha256: Digest::SHA256.hexdigest("no"), edit_token_digest: "y",
                     expires_at: 3.days.from_now, blocked_at: Time.current)

    stats = Stats.new

    assert_equal 2, stats.artifacts[:total]
    assert_equal 1, stats.artifacts[:live]
    assert_equal 1, stats.artifacts[:blocked]
    assert_equal Stats::DAYS, stats.per_day.size
    assert_equal 2, stats.per_day.last.last
    assert_equal({ users(:member).id => 1 }, stats.top_creators)
    assert_equal 1, stats.users[:with_artifacts]
    assert_equal live.byte_size + 9, stats.storage[:bytes]
  end
end
