module Admin
  class UsersController < BaseController
    def index
      @users = User.left_joins(:artifacts)
                   .select("users.*, COUNT(artifacts.id) AS artifacts_count")
                   .group("users.id")
                   .order(created_at: :desc)
    end

    # Role flip is the only edit the admin area needs; everything else about a
    # user is theirs to change.
    def update
      user = User.find(params[:id])

      if user == current_user
        redirect_to admin_users_path, alert: "You cannot change your own role."
      elsif user.update(role: params.require(:user).require(:role))
        redirect_to admin_users_path, notice: "#{user.email} is now #{user.role}."
      else
        redirect_to admin_users_path, alert: user.errors.full_messages.to_sentence
      end
    end
  end
end
