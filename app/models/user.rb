class User < ApplicationRecord
  ROLES = %w[user admin].freeze

  # No :registerable or :recoverable — accounts exist only to gate /admin, so
  # public signup and password reset would be unauthenticated, unrate-limited
  # endpoints buying nothing. db:seed makes the first admin, /admin/users the rest.
  devise :database_authenticatable, :rememberable, :validatable

  has_many :artifacts, dependent: :nullify

  validates :role, inclusion: { in: ROLES }

  scope :admins, -> { where(role: "admin") }

  def admin? = role == "admin"
end
