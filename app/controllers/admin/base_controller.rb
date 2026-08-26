module Admin
  # Every admin page hangs off this: signed in, and role == admin. Replaces the
  # shared ENV password the area used before, so takedowns are attributable.
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin

    private
      def require_admin
        redirect_to root_path, alert: "Admins only." unless current_user.admin?
      end
  end
end
