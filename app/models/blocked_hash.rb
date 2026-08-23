# Exact-match blocklist: once something is taken down, re-uploading the same bytes
# fails instantly and for free.
#
# ponytail: exact SHA-256, so a single flipped byte evades it. Perceptual hashing
# (PhotoDNA / pHash) is the upgrade path when re-uploads start mutating.
class BlockedHash < ApplicationRecord
  KINDS = %w[artifact image].freeze

  validates :sha256, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }

  def self.blocks?(digests)
    digests.any? && where(sha256: digests).exists?
  end

  # Records the artifact's own bytes and every image embedded in it.
  def self.record_artifact!(artifact, reason:)
    rows = [ { sha256: artifact.sha256, kind: "artifact" } ]
    rows += Artifact.embedded_image_digests(artifact.source_html).map { |digest| { sha256: digest, kind: "image" } }

    insert_all(rows.uniq { |row| row[:sha256] }.map { |row| row.merge(reason: reason, created_at: Time.current) })
  end
end
