require "controllers/api/v1/test"

class Api::V1::AppSecurityPoliciesControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = create(:app, team: @team)
    @app_security_policy = build(:app_security_policy, app: @app)
    @other_app_security_policies = create_list(:app_security_policy, 3)

    @another_app_security_policy = create(:app_security_policy, app: @app)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_security_policy.save
    @another_app_security_policy.save

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
  def assert_proper_object_serialization(app_security_policy_data)
    # Fetch the app_security_policy in question and prepare to compare it's attributes.
    app_security_policy = AppSecurityPolicy.find(app_security_policy_data["id"])

    assert_equal_or_nil app_security_policy_data["policy_name"], app_security_policy.policy_name
    assert_equal_or_nil app_security_policy_data["policy_type"], app_security_policy.policy_type
    assert_equal_or_nil app_security_policy_data["enabled"], app_security_policy.enabled
    assert_equal_or_nil app_security_policy_data["configuration"], app_security_policy.configuration
    assert_equal_or_nil app_security_policy_data["description"], app_security_policy.description
    assert_equal_or_nil DateTime.parse(app_security_policy_data["last_violation"]), app_security_policy.last_violation
    assert_equal_or_nil app_security_policy_data["violation_count"], app_security_policy.violation_count
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_security_policy_data["app_id"], app_security_policy.app_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}/app_security_policies", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_security_policy_ids_returned = response.parsed_body.map { |app_security_policy| app_security_policy["id"] }
    assert_includes(app_security_policy_ids_returned, @app_security_policy.id)

    # But not returning other people's resources.
    assert_not_includes(app_security_policy_ids_returned, @other_app_security_policies[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_security_policies/#{@app_security_policy.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_security_policies/#{@app_security_policy.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_security_policy_data = JSON.parse(build(:app_security_policy, app: nil).api_attributes.to_json)
    app_security_policy_data.except!("id", "app_id", "created_at", "updated_at")
    params[:app_security_policy] = app_security_policy_data

    post "/api/v1/apps/#{@app.id}/app_security_policies", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/apps/#{@app.id}/app_security_policies",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_security_policies/#{@app_security_policy.id}", params: {
      access_token: access_token,
      app_security_policy: {
        policy_name: "Alternative String Value",
        policy_type: "Alternative String Value",
        configuration: "Alternative String Value",
        description: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_security_policy.reload
    assert_equal @app_security_policy.policy_name, "Alternative String Value"
    assert_equal @app_security_policy.policy_type, "Alternative String Value"
    assert_equal @app_security_policy.configuration, "Alternative String Value"
    assert_equal @app_security_policy.description, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_security_policies/#{@app_security_policy.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppSecurityPolicy.count", -1) do
      delete "/api/v1/app_security_policies/#{@app_security_policy.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_security_policies/#{@another_app_security_policy.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
