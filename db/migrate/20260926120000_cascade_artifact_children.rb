# PurgeExpiredArtifactsJob deletes in bulk, which skips `dependent:` callbacks, so
# the database has to take the children with it. Without this the first expired
# artifact with a comment or a report raised ForeignKeyViolation and stopped the
# whole purge — and the IP scrub that runs after it.
class CascadeArtifactChildren < ActiveRecord::Migration[8.1]
  def change
    remove_foreign_key :comments, :artifacts
    add_foreign_key :comments, :artifacts, on_delete: :cascade

    remove_foreign_key :abuse_reports, :artifacts
    add_foreign_key :abuse_reports, :artifacts, on_delete: :cascade
  end
end
