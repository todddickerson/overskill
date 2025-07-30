require "controllers/api/v1/test"

class Api::V1::AppCollaboratorsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = create(:app, team: @team)
    @app_collaborator = build(:app_collaborator, app: @app)
    @other_app_collaborators = create_list(:app_collaborator, 3)

    @another_app_collaborator = create(:app_collaborator, app: @app)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_collaborator.save
    @another_app_collaborator.save

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
  def assert_proper_object_serialization(app_collaborator_data)
    # Fetch the app_collaborator in question and prepare to compare it's attributes.
    app_collaborator = AppCollaborator.find(app_collaborator_data["id"])

    assert_equal_or_nil app_collaborator_data["membership"], app_collaborator.membership
    assert_equal_or_nil app_collaborator_data["role"], app_collaborator.role
    assert_equal_or_nil app_collaborator_data["github_username"], app_collaborator.github_username
    assert_equal_or_nil app_collaborator_data["permissions_synced"], app_collaborator.permissions_synced
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_collaborator_data["app_id"], app_collaborator.app_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}/app_collaborators", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_collaborator_ids_returned = response.parsed_body.map { |app_collaborator| app_collaborator["id"] }
    assert_includes(app_collaborator_ids_returned, @app_collaborator.id)

    # But not returning other people's resources.
    assert_not_includes(app_collaborator_ids_returned, @other_app_collaborators[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_collaborators/#{@app_collaborator.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_collaborators/#{@app_collaborator.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_collaborator_data = JSON.parse(build(:app_collaborator, app: nil).api_attributes.to_json)
    app_collaborator_data.except!("id", "app_id", "created_at", "updated_at")
    params[:app_collaborator] = app_collaborator_data

    post "/api/v1/apps/#{@app.id}/app_collaborators", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/apps/#{@app.id}/app_collaborators",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_collaborators/#{@app_collaborator.id}", params: {
      access_token: access_token,
      app_collaborator: {
        role: "Alternative String Value",
        github_username: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_collaborator.reload
    assert_equal @app_collaborator.role, "Alternative String Value"
    assert_equal @app_collaborator.github_username, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_collaborators/#{@app_collaborator.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppCollaborator.count", -1) do
      delete "/api/v1/app_collaborators/#{@app_collaborator.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_collaborators/#{@another_app_collaborator.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
