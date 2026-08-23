# Serving already answers 410 the moment an artifact expires; this only reclaims
# the disk it was sitting on.
class PurgeExpiredArtifactsJob < ApplicationJob
  queue_as :default

  def perform
    Artifact.where(expires_at: ..Time.current).in_batches.delete_all

    # An artifact whose TTL keeps being extended would otherwise hold its uploader's
    # IP indefinitely. Retention is counted from upload, not from expiry.
    Artifact.where(created_at: ..Artifact::IP_RETENTION.ago)
            .where.not(creator_ip: nil)
            .in_batches.update_all(creator_ip: nil)
  end
end
