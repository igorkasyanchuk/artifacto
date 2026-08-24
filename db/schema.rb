# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_24_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "abuse_reports", force: :cascade do |t|
    t.bigint "artifact_id", null: false
    t.datetime "created_at", null: false
    t.text "details"
    t.datetime "handled_at"
    t.string "reason", null: false
    t.string "reporter_ip_hash"
    t.datetime "updated_at", null: false
    t.index ["artifact_id"], name: "index_abuse_reports_on_artifact_id"
  end

  create_table "artifacts", force: :cascade do |t|
    t.boolean "allow_network", default: false, null: false
    t.datetime "blocked_at"
    t.integer "byte_size", null: false
    t.binary "content", null: false
    t.datetime "created_at", null: false
    t.text "creator_ip"
    t.string "creator_ip_hash"
    t.string "edit_token_digest", null: false
    t.datetime "expires_at", null: false
    t.string "format", default: "html", null: false
    t.string "pin_digest"
    t.string "sha256", null: false
    t.string "slug", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.integer "view_count", default: 0, null: false
    t.index ["creator_ip_hash"], name: "index_artifacts_on_creator_ip_hash"
    t.index ["expires_at"], name: "index_artifacts_on_expires_at"
    t.index ["slug"], name: "index_artifacts_on_slug", unique: true
  end

  create_table "blocked_hashes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", default: "artifact", null: false
    t.string "reason"
    t.string "sha256", null: false
    t.index ["sha256"], name: "index_blocked_hashes_on_sha256", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "artifact_id", null: false
    t.string "author_ip_hash"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.text "quote"
    t.string "selector", null: false
    t.datetime "updated_at", null: false
    t.index ["artifact_id", "created_at"], name: "index_comments_on_artifact_id_and_created_at"
    t.index ["artifact_id"], name: "index_comments_on_artifact_id"
  end

  add_foreign_key "abuse_reports", "artifacts"
  add_foreign_key "comments", "artifacts"
end
