require "test_helper"

class PurgeExpiredArtifactsJobTest < ActiveJob::TestCase
  test "deletes expired artifacts and leaves live ones alone" do
    live = Artifact.create_from_source!("<html><body>live</body></html>")
    dead = Artifact.create_from_source!("<html><body>dead</body></html>")
    dead.update_column(:expires_at, 1.minute.ago)

    PurgeExpiredArtifactsJob.new.perform

    assert Artifact.exists?(live.id)
    assert_not Artifact.exists?(dead.id)
  end

  test "scrubs uploader IPs past the retention window, even on extended artifacts" do
    old = Artifact.create_from_source!("<html><body>old</body></html>", creator_ip: "203.0.113.1")
    old.update_columns(created_at: (Artifact::IP_RETENTION + 1.day).ago, expires_at: 5.days.from_now)
    recent = Artifact.create_from_source!("<html><body>new</body></html>", creator_ip: "203.0.113.2")

    PurgeExpiredArtifactsJob.new.perform

    assert_nil old.reload.creator_ip
    assert_equal "203.0.113.2", recent.reload.creator_ip
  end
end
