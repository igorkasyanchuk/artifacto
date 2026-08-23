class AddModeration < ActiveRecord::Migration[8.1]
  def change
    # Encrypted at rest, scrubbed after 30 days. The HMAC stays for banning; this
    # exists only so a lawful request about a specific artifact can be answered.
    add_column :artifacts, :creator_ip, :text

    create_table :blocked_hashes do |t|
      t.string   :sha256, null: false
      t.string   :kind,   null: false, default: "artifact"  # artifact | image
      t.string   :reason
      t.datetime :created_at, null: false
    end

    add_index :blocked_hashes, :sha256, unique: true
  end
end
