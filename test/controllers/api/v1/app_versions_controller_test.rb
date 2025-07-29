require "controllers/api/v1/test"

class Api::V1::AppVersionsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app_version = build(:app_version, team: @team)
    @other_app_versions = create_list(:app_version, 3)

    @another_app_version = create(:app_version, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_version.save
    @another_app_version.save

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
  def assert_proper_object_serialization(app_version_data)
    # Fetch the app_version in question and prepare to compare it's attributes.
    app_version = AppVersion.find(app_version_data["id"])

    assert_equal_or_nil app_version_data['app_id'], app_version.app_id
    assert_equal_or_nil app_version_data['user_id'], app_version.user_id
    assert_equal_or_nil app_version_data['commit_sha'], app_version.commit_sha
    assert_equal_or_nil app_version_data['commit_message'], app_version.commit_message
    assert_equal_or_nil app_version_data['version_number'], app_version.version_number
    assert_equal_or_nil app_version_data['changelog'], app_version.changelog
    assert_equal_or_nil app_version_data['files_snapshot'], app_version.files_snapshot
    assert_equal_or_nil app_version_data['changed_files'], app_version.changed_files
    assert_equal_or_nil app_version_data['external_commit'], app_version.external_commit
    assert_equal_or_nil app_version_data['deployed'], app_version.deployed
    assert_equal_or_nil DateTime.parse(app_version_data['published_at']), app_version.published_at
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_version_data["team_id"], app_version.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/app_versions", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_version_ids_returned = response.parsed_body.map { |app_version| app_version["id"] }
    assert_includes(app_version_ids_returned, @app_version.id)

    # But not returning other people's resources.
    assert_not_includes(app_version_ids_returned, @other_app_versions[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_versions/#{@app_version.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_versions/#{@app_version.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_version_data = JSON.parse(build(:app_version, team: nil).api_attributes.to_json)
    app_version_data.except!("id", "team_id", "created_at", "updated_at")
    params[:app_version] = app_version_data

    post "/api/v1/teams/#{@team.id}/app_versions", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/app_versions",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_versions/#{@app_version.id}", params: {
      access_token: access_token,
      app_version: {
        commit_sha: 'Alternative String Value',
        commit_message: 'Alternative String Value',
        version_number: 'Alternative String Value',
        changelog: 'Alternative String Value',
        files_snapshot: 'Alternative String Value',
        changed_files: 'Alternative String Value',
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_version.reload
    assert_equal @app_version.commit_sha, 'Alternative String Value'
    assert_equal @app_version.commit_message, 'Alternative String Value'
    assert_equal @app_version.version_number, 'Alternative String Value'
    assert_equal @app_version.changelog, 'Alternative String Value'
    assert_equal @app_version.files_snapshot, 'Alternative String Value'
    assert_equal @app_version.changed_files, 'Alternative String Value'
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_versions/#{@app_version.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppVersion.count", -1) do
      delete "/api/v1/app_versions/#{@app_version.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_versions/#{@another_app_version.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
