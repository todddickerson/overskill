require "controllers/api/v1/test"

class Api::V1::AppSettingsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = create(:app, team: @team)
    @app_setting = build(:app_setting, app: @app)
    @other_app_settings = create_list(:app_setting, 3)

    @another_app_setting = create(:app_setting, app: @app)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_setting.save
    @another_app_setting.save

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
  def assert_proper_object_serialization(app_setting_data)
    # Fetch the app_setting in question and prepare to compare it's attributes.
    app_setting = AppSetting.find(app_setting_data["id"])

    assert_equal_or_nil app_setting_data["key"], app_setting.key
    assert_equal_or_nil app_setting_data["value"], app_setting.value
    assert_equal_or_nil app_setting_data["setting_type"], app_setting.setting_type
    assert_equal_or_nil app_setting_data["description"], app_setting.description
    assert_equal_or_nil app_setting_data["encrypted"], app_setting.encrypted
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_setting_data["app_id"], app_setting.app_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}/app_settings", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_setting_ids_returned = response.parsed_body.map { |app_setting| app_setting["id"] }
    assert_includes(app_setting_ids_returned, @app_setting.id)

    # But not returning other people's resources.
    assert_not_includes(app_setting_ids_returned, @other_app_settings[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_settings/#{@app_setting.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_settings/#{@app_setting.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_setting_data = JSON.parse(build(:app_setting, app: nil).api_attributes.to_json)
    app_setting_data.except!("id", "app_id", "created_at", "updated_at")
    params[:app_setting] = app_setting_data

    post "/api/v1/apps/#{@app.id}/app_settings", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/apps/#{@app.id}/app_settings",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_settings/#{@app_setting.id}", params: {
      access_token: access_token,
      app_setting: {
        key: "Alternative String Value",
        value: "Alternative String Value",
        setting_type: "Alternative String Value",
        description: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_setting.reload
    assert_equal @app_setting.key, "Alternative String Value"
    assert_equal @app_setting.value, "Alternative String Value"
    assert_equal @app_setting.setting_type, "Alternative String Value"
    assert_equal @app_setting.description, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_settings/#{@app_setting.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppSetting.count", -1) do
      delete "/api/v1/app_settings/#{@app_setting.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_settings/#{@another_app_setting.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
