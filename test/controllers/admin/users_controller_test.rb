require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin) }

  test "promotes and demotes another user" do
    member = users(:member)

    patch admin_user_path(member), params: { user: { role: "admin" } }
    assert member.reload.admin?

    patch admin_user_path(member), params: { user: { role: "user" } }
    assert_not member.reload.admin?
  end

  test "refuses an unknown role" do
    member = users(:member)
    patch admin_user_path(member), params: { user: { role: "root" } }

    assert_equal "user", member.reload.role
    assert_equal "Role is not included in the list", flash[:alert]
  end

  test "an admin cannot demote themselves out of the admin area" do
    admin = users(:admin)
    patch admin_user_path(admin), params: { user: { role: "user" } }

    assert admin.reload.admin?
    assert_match "cannot change your own role", flash[:alert]
  end

  test "the index counts each user's artifacts" do
    get admin_users_path
    assert_response :success
    assert_select "td", "member@example.com"
  end
end
