class CreateArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :artifacts do |t|
      t.string   :slug,              null: false
      t.string   :edit_token_digest, null: false
      t.binary   :content,           null: false                   # gzipped HTML, ready to serve
      t.string   :format,            null: false, default: "html"  # html | markdown
      t.integer  :byte_size,         null: false                   # size before compression
      t.string   :sha256,            null: false                   # ETag source
      t.string   :title
      t.boolean  :allow_network,     null: false, default: false
      t.string   :pin_digest
      t.datetime :expires_at,        null: false
      t.datetime :blocked_at
      t.integer  :view_count,        null: false, default: 0
      t.string   :creator_ip_hash                                  # HMAC(ip), never the raw IP
      t.bigint   :user_id                                          # accounts land in phase 3

      t.timestamps
    end

    add_index :artifacts, :slug, unique: true
    add_index :artifacts, :expires_at
    add_index :artifacts, :creator_ip_hash

    create_table :abuse_reports do |t|
      t.references :artifact, null: false, foreign_key: true
      t.string     :reason, null: false   # phishing | malware | spam | other
      t.text       :details
      t.string     :reporter_ip_hash
      t.datetime   :handled_at

      t.timestamps
    end
  end
end
