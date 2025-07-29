require "controllers/api/v1/test"

class Api::V1::FollowsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @follow = build(:follow, team: @team)
    @other_follows = create_list(:follow, 3)

    @another_follow = create(:follow, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @follow.save
    @another_follow.save

    @original_hide_things = ENV["HIDE_THINGS"]
    ENV["HIDE_THINGS"] = "false"
    Rails.application.reload_routes!
  end

  teardown do
    ENV["HIDE_THINGS"] = @original_hide_things
    Rails.application.reload_routes!
  end

  # This assertion is written in such a way that new attributes won't cause the tests to start failing, but removing
  # data we were previously providing to users _will_ break the test suite.
  def assert_proper_object_serialization(follow_data)
    # Fetch the follow in question and prepare to compare it's attributes.
    follow = Follow.find(follow_data["id"])

    assert_equal_or_nil follow_data['follower_id'], follow.follower_id
    assert_equal_or_nil follow_data['followed_id'], follow.followed_id
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal follow_data["team_id"], follow.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/follows", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    follow_ids_returned = response.parsed_body.map { |follow| follow["id"] }
    assert_includes(follow_ids_returned, @follow.id)

    # But not returning other people's resources.
    assert_not_includes(follow_ids_returned, @other_follows[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/follows/#{@follow.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/follows/#{@follow.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    follow_data = JSON.parse(build(:follow, team: nil).api_attributes.to_json)
    follow_data.except!("id", "team_id", "created_at", "updated_at")
    params[:follow] = follow_data

    post "/api/v1/teams/#{@team.id}/follows", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/follows",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/follows/#{@follow.id}", params: {
      access_token: access_token,
      follow: {
        follower_id: 'Alternative String Value',
        followed_id: 'Alternative String Value',
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @follow.reload
    assert_equal @follow.follower_id, 'Alternative String Value'
    assert_equal @follow.followed_id, 'Alternative String Value'
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/follows/#{@follow.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("Follow.count", -1) do
      delete "/api/v1/follows/#{@follow.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/follows/#{@another_follow.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
