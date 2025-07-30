require "controllers/api/v1/test"

class Api::V1::AppsControllerTest < Api::Test
  setup do
    # See `test/controllers/api/test.rb` for common set up for API tests.

    @app = build(:app, team: @team)
    @other_apps = create_list(:app, 3)

    @another_app = create(:app, team: @team)

    # 🚅 super scaffolding will insert file-related logic above this line.
    @app.save
    @another_app.save

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
  def assert_proper_object_serialization(app_data)
    # Fetch the app in question and prepare to compare it's attributes.
    app = App.find(app_data["id"])

    assert_equal_or_nil app_data["name"], app.name
    assert_equal_or_nil app_data["slug"], app.slug
    assert_equal_or_nil app_data["description"], app.description
    assert_equal_or_nil app_data["creator_id"], app.creator_id
    assert_equal_or_nil app_data["prompt"], app.prompt
    assert_equal_or_nil app_data["app_type"], app.app_type
    assert_equal_or_nil app_data["framework"], app.framework
    assert_equal_or_nil app_data["status"], app.status
    assert_equal_or_nil app_data["visibility"], app.visibility
    assert_equal_or_nil app_data["base_price"], app.base_price
    assert_equal_or_nil app_data["stripe_product_id"], app.stripe_product_id
    assert_equal_or_nil app_data["preview_url"], app.preview_url
    assert_equal_or_nil app_data["production_url"], app.production_url
    assert_equal_or_nil app_data["github_repo"], app.github_repo
    assert_equal_or_nil app_data["total_users"], app.total_users
    assert_equal_or_nil app_data["total_revenue"], app.total_revenue
    assert_equal_or_nil app_data["rating"], app.rating
    assert_equal_or_nil app_data["featured"], app.featured
    assert_equal_or_nil DateTime.parse(app_data["featured_until"]), app.featured_until
    assert_equal_or_nil DateTime.parse(app_data["launch_date"]), app.launch_date
    assert_equal_or_nil app_data["ai_model"], app.ai_model
    assert_equal_or_nil app_data["ai_cost"], app.ai_cost
    # 🚅 super scaffolding will insert new fields above this line.

    assert_equal app_data["team_id"], app.team_id
  end

  test "index" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/teams/#{@team.id}/apps", params: {access_token: access_token}
    assert_response :success

    # Make sure it's returning our resources.
    app_ids_returned = response.parsed_body.map { |app| app["id"] }
    assert_includes(app_ids_returned, @app.id)

    # But not returning other people's resources.
    assert_not_includes(app_ids_returned, @other_apps[0].id)

    # And that the object structure is correct.
    assert_proper_object_serialization response.parsed_body.first
  end

  test "show" do
    # Fetch and ensure nothing is seriously broken.
    get "/api/v1/apps/#{@app.id}", params: {access_token: access_token}
    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    get "/api/v1/apps/#{@app.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "create" do
    # Use the serializer to generate a payload, but strip some attributes out.
    params = {access_token: access_token}
    app_data = JSON.parse(build(:app, team: nil).api_attributes.to_json)
    app_data.except!("id", "team_id", "created_at", "updated_at")
    params[:app] = app_data

    post "/api/v1/teams/#{@team.id}/apps", params: params
    assert_response :success

    # # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # Also ensure we can't do that same action as another user.
    post "/api/v1/teams/#{@team.id}/apps",
      params: params.merge({access_token: another_access_token})
    assert_response :not_found
  end

  test "update" do
    # Post an attribute update ensure nothing is seriously broken.
    put "/api/v1/apps/#{@app.id}", params: {
      access_token: access_token,
      app: {
        name: "Alternative String Value",
        slug: "Alternative String Value",
        description: "Alternative String Value",
        prompt: "Alternative String Value",
        stripe_product_id: "Alternative String Value",
        preview_url: "Alternative String Value",
        production_url: "Alternative String Value",
        github_repo: "Alternative String Value",
        # 🚅 super scaffolding will also insert new fields above this line.
      }
    }

    assert_response :success

    # Ensure all the required data is returned properly.
    assert_proper_object_serialization response.parsed_body

    # But we have to manually assert the value was properly updated.
    @app.reload
    assert_equal @app.name, "Alternative String Value"
    assert_equal @app.slug, "Alternative String Value"
    assert_equal @app.description, "Alternative String Value"
    assert_equal @app.prompt, "Alternative String Value"
    assert_equal @app.stripe_product_id, "Alternative String Value"
    assert_equal @app.preview_url, "Alternative String Value"
    assert_equal @app.production_url, "Alternative String Value"
    assert_equal @app.github_repo, "Alternative String Value"
    # 🚅 super scaffolding will additionally insert new fields above this line.

    # Also ensure we can't do that same action as another user.
    put "/api/v1/apps/#{@app.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end

  test "destroy" do
    # Delete and ensure it actually went away.
    assert_difference("App.count", -1) do
      delete "/api/v1/apps/#{@app.id}", params: {access_token: access_token}
      assert_response :success
    end

    # Also ensure we can't do that same action as another user.
    delete "/api/v1/apps/#{@another_app.id}", params: {access_token: another_access_token}
    assert_response :not_found
  end
end
