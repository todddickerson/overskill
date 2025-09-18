require "controllers/api/v1/test"

class Api::V1::AppEnvVarsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = create(:app, team: @team)
    @app_env_var = build(:app_env_var, app: @app)
    @other_app_env_vars = create_list(:app_env_var, 3)

    @another_app_env_var = create(:app_env_var, app: @app)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_env_var.save
    @another_app_env_var.save

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
  def assert_proper_object_serialization(app_env_var_data)
    # Fetch the app_env_var in question and prepare to compare it's attributes.
    app_env_var = AppEnvVar.find(app_env_var_data["id"])

    assert_equal_or_nil app_env_var_data["key"], app_env_var.key
    assert_equal_or_nil app_env_var_data["value"], app_env_var.value
    assert_equal_or_nil app_env_var_data["description"], app_env_var.description
    assert_equal_or_nil app_env_var_data["is_secret"], app_env_var.is_secret
    assert_equal_or_nil app_env_var_data["is_system"], app_env_var.is_system
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_env_var_data["app_id"], app_env_var.app_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}/app_env_vars", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_env_var_ids_returned = response.parsed_body.map { |app_env_var| app_env_var["id"] }
    assert_includes(app_env_var_ids_returned, @app_env_var.id)

    # But not returning other people's resources.
    assert_not_includes(app_env_var_ids_returned, @other_app_env_vars[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_env_vars/#{@app_env_var.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_env_vars/#{@app_env_var.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_env_var_data = JSON.parse(build(:app_env_var, app: nil).api_attributes.to_json)
    app_env_var_data.except!("id", "app_id", "created_at", "updated_at")
    params[:app_env_var] = app_env_var_data

    post "/api/v1/apps/#{@app.id}/app_env_vars", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/apps/#{@app.id}/app_env_vars",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_env_vars/#{@app_env_var.id}", params: {
      access_token: access_token,
      app_env_var: {
        key: "Alternative String Value",
        value: "Alternative String Value",
        description: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_env_var.reload
    assert_equal @app_env_var.key, "Alternative String Value"
    assert_equal @app_env_var.value, "Alternative String Value"
    assert_equal @app_env_var.description, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_env_vars/#{@app_env_var.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppEnvVar.count", -1) do
      delete "/api/v1/app_env_vars/#{@app_env_var.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_env_vars/#{@another_app_env_var.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
