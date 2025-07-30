require "test_helper"

class Account::AppEditorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @team = teams(:one)
    @app = apps(:one)
    @app.update!(team: @team, status: "generated")
    
    # Create test files
    @app_file = app_files(:one)
    @app_file.update!(app: @app, path: "index.html", content: "<h1>Test</h1>")
    
    sign_in @user
  end

  test "should get show for generated app" do
    get account_app_editor_url(@app)
    assert_response :success
    
    # Check that necessary instance variables are set
    assert_not_nil assigns(:app)
    assert_not_nil assigns(:chat_messages)
    assert_not_nil assigns(:files)
  end

  test "should redirect if app not generated" do
    @app.update!(status: "generating")
    
    get account_app_editor_url(@app)
    assert_redirected_to account_app_path(@app)
    assert_equal "App is still being generated. Please wait...", flash[:alert]
  end

  test "should create chat message" do
    assert_difference("AppChatMessage.count") do
      post account_app_chat_messages_url(@app), params: {
        message: "Add a button"
      }, as: :turbo_stream
    end
    
    assert_response :success
    
    message = AppChatMessage.last
    assert_equal "user", message.role
    assert_equal "Add a button", message.content
    assert_equal "pending", message.status
  end

  test "should update file content" do
    patch account_app_file_url(@app, @app_file), params: {
      content: "<h1>Updated</h1>"
    }, as: :json
    
    assert_response :success
    
    @app_file.reload
    assert_equal "<h1>Updated</h1>", @app_file.content
    
    json_response = JSON.parse(response.body)
    assert json_response["success"]
    assert_equal "File updated", json_response["message"]
  end

  test "should handle file update errors" do
    # Try to update with nil content
    patch account_app_file_url(@app, @app_file), params: {
      content: nil
    }, as: :json
    
    assert_response :unprocessable_entity
    
    json_response = JSON.parse(response.body)
    assert_not json_response["success"]
    assert json_response["error"]
  end

  test "should require authentication" do
    sign_out @user
    
    get account_app_editor_url(@app)
    assert_redirected_to new_user_session_path
  end

  test "should enforce team permissions" do
    other_team = teams(:two)
    other_app = apps(:two)
    other_app.update!(team: other_team)
    
    get account_app_editor_url(other_app)
    assert_response :not_found
  end

  test "should show preview for HTML files" do
    get account_app_editor_url(@app)
    
    assert_select "#preview_frame"
    assert_select "iframe[src*='preview']"
  end

  test "should list all app files" do
    # Create additional files
    @app.app_files.create!(
      path: "app.js",
      content: "console.log('test');",
      file_type: "javascript",
      size_bytes: 20
    )
    
    @app.app_files.create!(
      path: "styles.css",
      content: "body { margin: 0; }",
      file_type: "css",
      size_bytes: 19
    )
    
    get account_app_editor_url(@app)
    
    assert_select "#files_list" do
      assert_select "[data-file-path='index.html']"
      assert_select "[data-file-path='app.js']"
      assert_select "[data-file-path='styles.css']"
    end
  end

  test "should handle turbo frame requests" do
    get account_app_editor_url(@app), headers: { "Turbo-Frame" => "preview_frame" }
    
    assert_response :success
    assert_match %r{<turbo-frame id="preview_frame">}, response.body
  end
end