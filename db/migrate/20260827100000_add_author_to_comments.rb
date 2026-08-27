class AddAuthorToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :author, :string
  end
end
