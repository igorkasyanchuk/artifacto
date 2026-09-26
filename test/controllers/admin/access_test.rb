require "test_helper"

class Admin::AccessTest < ActionDispatch::IntegrationTest
  test "signed-out visitors are sent to the sign-in page" do
    get admin_root_path
    assert_redirected_to new_user_session_path
  end

  test "plain users are bounced off every admin page" do
    sign_in users(:member)

    [ admin_root_path, admin_artifacts_path, admin_comments_path, admin_users_path ].each do |path|
      get path
      assert_redirected_to root_path
    end
  end

  test "there is no public signup or password reset" do
    get "/users/sign_up"
    assert_response :not_found

    get "/users/password/new"
    assert_response :not_found
  end

  test "sign-in guesses run out" do
    10.times { post user_session_path, params: { user: { email: "admin@example.com", password: "wrong" } } }
    post user_session_path, params: { user: { email: "admin@example.com", password: "password" } }

    assert_redirected_to new_user_session_path
    assert_equal "Too many attempts, try again later.", flash[:alert]
  end

  test "admins get the dashboard" do
    sign_in users(:admin)
    get admin_root_path

    assert_response :success
    assert_select "h1", "Admin"
  end
end
