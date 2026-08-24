# Reader feedback anchored to a spot in the artifact.
#
# `selector` is the nth-of-type chain the injected agent produced at click time.
# A PUT replaces the artifact body wholesale, so that chain is expected to rot;
# `quote` is stored beside it and the agent re-anchors on the text when the
# selector no longer resolves. Neither is trusted — both come from the frame.
class Comment < ApplicationRecord
  MAX_BODY = 2_000
  MAX_QUOTE = 200
  MAX_SELECTOR = 500
  # Second guard behind the per-IP rate limit: one artifact cannot become free
  # storage. ponytail: a flat cap, not a quota — revisit if it ever bites.
  MAX_PER_ARTIFACT = 500

  belongs_to :artifact

  validates :body, presence: true, length: { maximum: MAX_BODY }
  validates :selector, presence: true, length: { maximum: MAX_SELECTOR }
  validates :quote, length: { maximum: MAX_QUOTE }

  scope :oldest_first, -> { order(:created_at, :id) }

  def as_json(*)
    {
      id: id,
      selector: selector,
      quote: quote,
      body: body,
      created_at: created_at.utc.iso8601
    }
  end
end
