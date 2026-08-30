# Reader feedback anchored to a spot in the artifact.
#
# `selector` is the nth-of-type chain the injected agent produced at click time.
# A PUT replaces the artifact body wholesale, so that chain is expected to rot;
# `quote` is stored beside it and the agent re-anchors on the text when the
# selector no longer resolves. Neither is trusted — both come from the frame.
class Comment < ApplicationRecord
  MAX_BODY = 2_000
  MAX_QUOTE = 200
  # Whatever the reader typed into the name box, kept because it makes a thread
  # readable — never a claim about who they are. Optional by design: no account
  # exists to check it against.
  MAX_AUTHOR = 60
  MAX_SELECTOR = 500
  # Second guard behind the per-IP rate limit: one artifact cannot become free
  # storage. ponytail: a flat cap, not a quota — revisit if it ever bites.
  MAX_PER_ARTIFACT = 500

  belongs_to :artifact

  validates :body, presence: true, length: { maximum: MAX_BODY }
  validates :selector, presence: true, length: { maximum: MAX_SELECTOR }
  validates :quote, length: { maximum: MAX_QUOTE }
  validates :author, length: { maximum: MAX_AUTHOR }

  scope :oldest_first, -> { order(:created_at, :id) }

  # Fractions of the anchor element's box, so they survive a change of window
  # width. Out-of-range values are the frame's word against ours: clamp rather
  # than reject, since a pin in the wrong place beats a comment refused.
  def self.fraction(value)
    return nil if value.blank?

    Float(value, exception: false)&.clamp(0.0, 1.0)
  end

  def as_json(*)
    {
      id: id,
      selector: selector,
      quote: quote,
      anchor_x: anchor_x,
      anchor_y: anchor_y,
      author: author,
      body: body,
      created_at: created_at.utc.iso8601
    }
  end
end
