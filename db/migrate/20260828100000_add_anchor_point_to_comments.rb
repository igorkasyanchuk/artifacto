# Where inside the anchor element the reader clicked, as a fraction of its box.
# Without it a comment on a large element — <body> above all — pins to that
# element's top-left corner rather than to the spot that was clicked.
#
# Null on every row written before this, and the overlay falls back to the
# corner for those, so no backfill is possible or needed here.
class AddAnchorPointToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :anchor_x, :float
    add_column :comments, :anchor_y, :float
  end
end
