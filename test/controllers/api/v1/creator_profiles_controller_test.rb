require "controllers/api/v1/test"

class Api::V1::CreatorProfilesControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @membership = create(:membership)
    @team = create(:team, membership: @membership)
    @creator_profile = build(:creator_profile, team: @team)
    @other_creator_profiles = create_list(:creator_profile, 3)

    @another_creator_profile = create(:creator_profile, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @creator_profile.save
    @another_creator_profile.save

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
  def assert_proper_object_serialization(creator_profile_data)
    # Fetch the creator_profile in question and prepare to compare it's attributes.
    creator_profile = CreatorProfile.find(creator_profile_data["id"])

    assert_equal_or_nil creator_profile_data['username'], creator_profile.username
    assert_equal_or_nil creator_profile_data['bio'], creator_profile.bio
    assert_equal_or_nil creator_profile_data['level'], creator_profile.level
    assert_equal_or_nil creator_profile_data['total_earnings'], creator_profile.total_earnings
    assert_equal_or_nil creator_profile_data['total_sales'], creator_profile.total_sales
    assert_equal_or_nil creator_profile_data['verification_status'], creator_profile.verification_status
    assert_equal_or_nil DateTime.parse(creator_profile_data['featured_until']), creator_profile.featured_until
    assert_equal_or_nil creator_profile_data['slug'], creator_profile.slug
    assert_equal_or_nil creator_profile_data['stripe_account_id'], creator_profile.stripe_account_id
    assert_equal_or_nil creator_profile_data['public_email'], creator_profile.public_email
    assert_equal_or_nil creator_profile_data['website_url'], creator_profile.website_url
    assert_equal_or_nil creator_profile_data['twitter_handle'], creator_profile.twitter_handle
    assert_equal_or_nil creator_profile_data['github_username'], creator_profile.github_username
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal creator_profile_data["team_id"], creator_profile.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/creator_profiles", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    creator_profile_ids_returned = response.parsed_body.map { |creator_profile| creator_profile["id"] }
    assert_includes(creator_profile_ids_returned, @creator_profile.id)

    # But not returning other people's resources.
    assert_not_includes(creator_profile_ids_returned, @other_creator_profiles[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/creator_profiles/#{@creator_profile.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/creator_profiles/#{@creator_profile.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    creator_profile_data = JSON.parse(build(:creator_profile, team: nil).api_attributes.to_json)
    creator_profile_data.except!("id", "team_id", "created_at", "updated_at")
    params[:creator_profile] = creator_profile_data

    post "/api/v1/teams/#{@team.id}/creator_profiles", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/creator_profiles",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/creator_profiles/#{@creator_profile.id}", params: {
      access_token: access_token,
      creator_profile: {
        username: 'Alternative String Value',
        bio: 'Alternative String Value',
        slug: 'Alternative String Value',
        stripe_account_id: 'Alternative String Value',
        public_email: 'another.email@test.com',
        website_url: 'Alternative String Value',
        twitter_handle: 'Alternative String Value',
        github_username: 'Alternative String Value',
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @creator_profile.reload
    assert_equal @creator_profile.username, 'Alternative String Value'
    assert_equal @creator_profile.bio, 'Alternative String Value'
    assert_equal @creator_profile.slug, 'Alternative String Value'
    assert_equal @creator_profile.stripe_account_id, 'Alternative String Value'
    assert_equal @creator_profile.public_email, 'another.email@test.com'
    assert_equal @creator_profile.website_url, 'Alternative String Value'
    assert_equal @creator_profile.twitter_handle, 'Alternative String Value'
    assert_equal @creator_profile.github_username, 'Alternative String Value'
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/creator_profiles/#{@creator_profile.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("CreatorProfile.count", -1) do
      delete "/api/v1/creator_profiles/#{@creator_profile.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/creator_profiles/#{@another_creator_profile.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
