require "controllers/api/v1/test"

class Api::V1::AppGenerationsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = create(:app, team: @team)
    @app_generation = build(:app_generation, app: @app)
    @other_app_generations = create_list(:app_generation, 3)

    @another_app_generation = create(:app_generation, app: @app)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app_generation.save
    @another_app_generation.save

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
  def assert_proper_object_serialization(app_generation_data)
    # Fetch the app_generation in question and prepare to compare it's attributes.
    app_generation = AppGeneration.find(app_generation_data["id"])

    assert_equal_or_nil app_generation_data["status"], app_generation.status
    assert_equal_or_nil app_generation_data["ai_model"], app_generation.ai_model
    assert_equal_or_nil app_generation_data["prompt"], app_generation.prompt
    assert_equal_or_nil app_generation_data["enhanced_prompt"], app_generation.enhanced_prompt
    assert_equal_or_nil DateTime.parse(app_generation_data["started_at"]), app_generation.started_at
    assert_equal_or_nil DateTime.parse(app_generation_data["completed_at"]), app_generation.completed_at
    assert_equal_or_nil app_generation_data["duration_seconds"], app_generation.duration_seconds
    assert_equal_or_nil app_generation_data["input_tokens"], app_generation.input_tokens
    assert_equal_or_nil app_generation_data["output_tokens"], app_generation.output_tokens
    assert_equal_or_nil app_generation_data["total_cost"], app_generation.total_cost
    assert_equal_or_nil app_generation_data["error_message"], app_generation.error_message
    assert_equal_or_nil app_generation_data["retry_count"], app_generation.retry_count
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_generation_data["app_id"], app_generation.app_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}/app_generations", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_generation_ids_returned = response.parsed_body.map { |app_generation| app_generation["id"] }
    assert_includes(app_generation_ids_returned, @app_generation.id)

    # But not returning other people's resources.
    assert_not_includes(app_generation_ids_returned, @other_app_generations[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/app_generations/#{@app_generation.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/app_generations/#{@app_generation.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_generation_data = JSON.parse(build(:app_generation, app: nil).api_attributes.to_json)
    app_generation_data.except!("id", "app_id", "created_at", "updated_at")
    params[:app_generation] = app_generation_data

    post "/api/v1/apps/#{@app.id}/app_generations", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/apps/#{@app.id}/app_generations",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/app_generations/#{@app_generation.id}", params: {
      access_token: access_token,
      app_generation: {
        status: "Alternative String Value",
        ai_model: "Alternative String Value",
        prompt: "Alternative String Value",
        enhanced_prompt: "Alternative String Value",
        error_message: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app_generation.reload
    assert_equal @app_generation.status, "Alternative String Value"
    assert_equal @app_generation.ai_model, "Alternative String Value"
    assert_equal @app_generation.prompt, "Alternative String Value"
    assert_equal @app_generation.enhanced_prompt, "Alternative String Value"
    assert_equal @app_generation.error_message, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/app_generations/#{@app_generation.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("AppGeneration.count", -1) do
      delete "/api/v1/app_generations/#{@app_generation.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/app_generations/#{@another_app_generation.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
