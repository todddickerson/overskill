require "test_helper"

class UserTest < ActiveSupport::TestCase
  setup do
    @user = User.new(email: "jane@bullettrain.co")
  end

  test "details_provided should be true when details are provided" do
    skip "details_provided? method not implemented"
    @user = FactoryBot.create :onboarded_user, first_name: "a", last_name: "b"
    assert @user.details_provided?
  end

  test "details_provided should be false when details aren't provided" do
    skip "details_provided? method not implemented"
    @user = FactoryBot.create :user, first_name: "a", last_name: nil
    assert_equal @user.details_provided?, false
  end
end
