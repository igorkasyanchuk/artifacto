class AbuseReport < ApplicationRecord
  REASONS = %w[phishing malware spam other].freeze

  belongs_to :artifact

  validates :reason, inclusion: { in: REASONS }
  validates :details, length: { maximum: 2_000 }

  scope :pending, -> { where(handled_at: nil) }
end
