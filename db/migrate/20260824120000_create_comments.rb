class CreateComments < ActiveRecord::Migration[8.1]
  def change
    create_table :comments do |t|
      t.references :artifact, null: false, foreign_key: true
      t.string     :selector, null: false   # nth-of-type chain produced by artifact_agent.js
      t.text       :quote                   # what the selector pointed at, so a PUT that breaks it can re-anchor
      t.text       :body, null: false
      t.string     :author_ip_hash          # HMAC(ip), same shape as abuse_reports. Accounts land in phase 3

      t.timestamps
    end

    add_index :comments, [ :artifact_id, :created_at ]
  end
end
