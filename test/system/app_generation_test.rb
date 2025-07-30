require "application_system_test_case"

class AppGenerationTest < ApplicationSystemTestCase
  setup do
    @user = create_user
    @team = @user.teams.first
    login_as(@user, scope: :user)
  end

  test "visiting the apps index" do
    visit account_team_apps_path(@team)

    assert_selector "h1", text: "Apps"
    assert_selector "a", text: "Add New App"
  end

  test "creating a new app" do
    visit account_team_apps_path(@team)
    click_on "Add New App"

    fill_in "Name", with: "My Test App"
    fill_in "Description", with: "A test application"
    fill_in "Prompt", with: "Create a simple counter app"
    select "utility", from: "App type"
    select "react", from: "Framework"

    click_on "Create App"

    assert_text "App was successfully created"
    assert_text "My Test App"

    # Should show generation status
    assert_selector "[data-turbo-stream-target]"
    assert_text "Generating"
  end

  test "viewing app editor for generated app" do
    app = apps(:generated_app)
    app.update!(team: @team)

    # Create some test files
    app.app_files.create!(
      path: "index.html",
      content: "<h1>Hello World</h1>",
      file_type: "html",
      size_bytes: 20
    )

    visit account_app_editor_path(app)

    # Check for split-screen layout
    assert_selector "#editor_container"
    assert_selector "#chat_sidebar"
    assert_selector "#content_area"

    # Check for tabs
    assert_selector "[data-tab='preview']"
    assert_selector "[data-tab='code']"
    assert_selector "[data-tab='files']"

    # Check preview iframe exists
    assert_selector "#preview_frame"
  end

  test "sending chat message in editor" do
    app = apps(:generated_app)
    app.update!(team: @team)

    visit account_app_editor_path(app)

    # Find and fill chat input
    within "#chat_form" do
      fill_in "message", with: "Add a dark mode toggle"
      click_button "Send"
    end

    # Should see the user message appear
    assert_selector "#chat_messages", text: "Add a dark mode toggle"

    # Should see processing indicator
    assert_selector "[id^='processing_']"
  end

  test "switching between tabs in editor" do
    app = apps(:generated_app)
    app.update!(team: @team)

    app.app_files.create!(
      path: "app.js",
      content: "console.log('test');",
      file_type: "javascript",
      size_bytes: 20
    )

    visit account_app_editor_path(app)

    # Default should show preview
    assert_selector "#preview_content", visible: true

    # Click on code tab
    click_on "Code"
    assert_selector "#code_content", visible: true
    assert_no_selector "#preview_content", visible: true

    # Click on files tab
    click_on "Files"
    assert_selector "#files_content", visible: true
    assert_text "app.js"
  end

  test "editing code in editor" do
    app = apps(:generated_app)
    app.update!(team: @team)

    file = app.app_files.create!(
      path: "index.html",
      content: "<h1>Original</h1>",
      file_type: "html",
      size_bytes: 17
    )

    visit account_app_editor_path(app)

    # Click on code tab
    click_on "Code"

    # Select the file
    within "#code_content" do
      click_on "index.html"
    end

    # Edit the content
    fill_in "file_content", with: "<h1>Updated</h1>"

    # Wait for auto-save (debounced)
    sleep 2

    # Verify the file was updated
    file.reload
    assert_equal "<h1>Updated</h1>", file.content
  end

  test "app generation status updates via turbo" do
    app = apps(:one)
    app.update!(team: @team, status: "generating")

    visit account_app_path(app)

    # Should see generation status
    assert_selector "#app_generation_status"
    assert_text "Generating your app"

    # Simulate status update via Turbo
    app.update!(status: "generated")

    # Broadcast the update (in real app this happens in job)
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}_generation",
      target: "app_generation_status",
      partial: "account/apps/generation_status",
      locals: {app: app, status: "generated", message: "Generation complete!"}
    )

    # Should see updated status
    assert_text "Generation complete!"
    assert_selector "a", text: "Open Editor"
  end

  private

  def create_user
    user = users(:one)
    user.update!(password: "password123")
    user
  end
end
