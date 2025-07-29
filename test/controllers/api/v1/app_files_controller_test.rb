require "controllers/api/v1/test"

class Api::V1::AppFilesControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app_file = build(:app_file, team: @team)
    @other_app_files = create_list(:app_file, 3)

    @another_app_file = create(:app_file, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_file.save
    @another_app_file.save

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
  def assert_proper_object_serialization(app_file_data)
    # Fetch the app_file in question and prepare to compare it's attributes.
    app_file = AppFile.find(app_file_data["id"])

    assert_equal_or_nil app_file_data['app_id'], app_file.app_id
    assert_equal_or_nil app_file_data['path'], app_file.path
    assert_equal_or_nil app_file_data['content'], app_file.content
    assert_equal_or_nil app_file_data['file_type'], app_file.file_type
    assert_equal_or_nil app_file_data['size_bytes'], app_file.size_bytes
    assert_equal_or_nil app_file_data['checksum'], app_file.checksum
    assert_equal_or_nil app_file_data['is_entry_point'], app_file.is_entry_point
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_file_data["team_id"], app_file.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/app_files", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_file_ids_returned = response.parsed_body.map { |app_file| app_file["id"] }
    assert_includes(app_file_ids_returned, @app_file.id)

    # But not returning other people's resources.
    assert_not_includes(app_file_ids_returned, @other_app_files[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_files/#{@app_file.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_files/#{@app_file.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_file_data = JSON.parse(build(:app_file, team: nil).api_attributes.to_json)
    app_file_data.except!("id", "team_id", "created_at", "updated_at")
    params[:app_file] = app_file_data

    post "/api/v1/teams/#{@team.id}/app_files", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/app_files",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_files/#{@app_file.id}", params: {
      access_token: access_token,
      app_file: {
        path: 'Alternative String Value',
        content: 'Alternative String Value',
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_file.reload
    assert_equal @app_file.path, 'Alternative String Value'
    assert_equal @app_file.content, 'Alternative String Value'
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_files/#{@app_file.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppFile.count", -1) do
      delete "/api/v1/app_files/#{@app_file.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_files/#{@another_app_file.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
