# frozen_string_literal: true

class DeviseCreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email,              null: false, default: ""
      t.string :encrypted_password, null: false, default: ""

      t.datetime :remember_created_at

      # Two roles only. A string keeps `where(role: "admin")` readable in psql,
      # which an integer enum would not.
      t.string :role, null: false, default: "user"

      t.timestamps null: false
    end

    add_index :users, :email, unique: true

    # The column predates the table; wire it up now that there is something to
    # point at. Nullable because anonymous uploads stay the common case.
    add_index :artifacts, :user_id
    add_foreign_key :artifacts, :users, on_delete: :nullify
  end
end
