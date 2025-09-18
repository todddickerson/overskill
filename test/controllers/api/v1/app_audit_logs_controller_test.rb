require "controllers/api/v1/test"

class Api::V1::AppAuditLogsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = create(:app, team: @team)
    @app_audit_log = build(:app_audit_log, app: @app)
    @other_app_audit_logs = create_list(:app_audit_log, 3)

    @another_app_audit_log = create(:app_audit_log, app: @app)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_audit_log.save
    @another_app_audit_log.save

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
  def assert_proper_object_serialization(app_audit_log_data)
    # Fetch the app_audit_log in question and prepare to compare it's attributes.
    app_audit_log = AppAuditLog.find(app_audit_log_data["id"])

    assert_equal_or_nil app_audit_log_data["action_type"], app_audit_log.action_type
    assert_equal_or_nil app_audit_log_data["performed_by"], app_audit_log.performed_by
    assert_equal_or_nil app_audit_log_data["target_resource"], app_audit_log.target_resource
    assert_equal_or_nil app_audit_log_data["resource_id"], app_audit_log.resource_id
    assert_equal_or_nil app_audit_log_data["change_details"], app_audit_log.change_details
    assert_equal_or_nil app_audit_log_data["ip_address"], app_audit_log.ip_address
    assert_equal_or_nil app_audit_log_data["user_agent"], app_audit_log.user_agent
    assert_equal_or_nil DateTime.parse(app_audit_log_data["occurred_at"]), app_audit_log.occurred_at
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_audit_log_data["app_id"], app_audit_log.app_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}/app_audit_logs", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_audit_log_ids_returned = response.parsed_body.map { |app_audit_log| app_audit_log["id"] }
    assert_includes(app_audit_log_ids_returned, @app_audit_log.id)

    # But not returning other people's resources.
    assert_not_includes(app_audit_log_ids_returned, @other_app_audit_logs[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_audit_logs/#{@app_audit_log.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_audit_logs/#{@app_audit_log.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_audit_log_data = JSON.parse(build(:app_audit_log, app: nil).api_attributes.to_json)
    app_audit_log_data.except!("id", "app_id", "created_at", "updated_at")
    params[:app_audit_log] = app_audit_log_data

    post "/api/v1/apps/#{@app.id}/app_audit_logs", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/apps/#{@app.id}/app_audit_logs",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_audit_logs/#{@app_audit_log.id}", params: {
      access_token: access_token,
      app_audit_log: {
        action_type: "Alternative String Value",
        target_resource: "Alternative String Value",
        resource_id: "Alternative String Value",
        change_details: "Alternative String Value",
        ip_address: "Alternative String Value",
        user_agent: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_audit_log.reload
    assert_equal @app_audit_log.action_type, "Alternative String Value"
    assert_equal @app_audit_log.target_resource, "Alternative String Value"
    assert_equal @app_audit_log.resource_id, "Alternative String Value"
    assert_equal @app_audit_log.change_details, "Alternative String Value"
    assert_equal @app_audit_log.ip_address, "Alternative String Value"
    assert_equal @app_audit_log.user_agent, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_audit_logs/#{@app_audit_log.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppAuditLog.count", -1) do
      delete "/api/v1/app_audit_logs/#{@app_audit_log.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_audit_logs/#{@another_app_audit_log.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
