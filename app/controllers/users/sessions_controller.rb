# The sign-in form is the one public way in to /admin, and Devise's lockable is
# off, so guesses are what has to be scarce.
#
# ponytail: per IP only. A per-account limit would stop a botnet too, but it also
# lets anyone who knows the admin's email lock them out in the middle of an abuse
# incident. A long ADMIN_PASSWORD covers the botnet case.
module Users
  class SessionsController < Devise::SessionsController
    rate_limit to: 10, within: 10.minutes, only: :create,
               with: -> { redirect_to new_user_session_path, alert: "Too many attempts, try again later." }
  end
end
