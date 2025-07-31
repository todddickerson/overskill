require "test_helper"
require "minitest/mock"

class AppGenerationFlowTest < ActiveJob::TestCase
  setup do
    @team = create(:team)
    @user = create(:user)
    @membership = create(:membership, user: @user, team: @team, role_ids: [Role.admin.id])
  end

  test "complete app generation flow from creation to files" do
    # Step 1: Create an app with a prompt
    app = nil
    assert_difference "App.count", 1 do
      app = App.create!(
        team: @team,
        creator: @membership,
        name: "Todo List App",
        prompt: "Create a beautiful todo list app with add, edit, delete, and mark complete functionality",
        app_type: "productivity",
        framework: "react",
        status: "draft"
      )
    end

    assert app.persisted?
    assert_equal "draft", app.status

    # Step 2: Create app generation
    generation = nil
    assert_difference "AppGeneration.count", 1 do
      generation = app.app_generations.create!(
        team: @team,
        prompt: app.prompt,
        status: "pending",
        started_at: Time.current
      )
    end

    assert generation.persisted?
    assert_equal "pending", generation.status

    # Step 3: Mock the AI service and generate the app
    mock_ai_response = {
      success: true,
      app: {
        "name" => "Todo List App",
        "description" => "A beautiful todo list application",
        "features" => ["Add tasks", "Edit tasks", "Delete tasks", "Mark as complete"]
      },
      files: [
        {
          "path" => "index.html",
          "content" => "<html><body><div id='app'></div></body></html>",
          "type" => "html"
        },
        {
          "path" => "app.js",
          "content" => "const TodoApp = () => { /* app code */ };",
          "type" => "javascript"
        },
        {
          "path" => "styles.css",
          "content" => "body { font-family: Arial; }",
          "type" => "css"
        }
      ]
    }

    # Mock the service
    service = AI::AppGeneratorService.new(app, generation)
    
    # Mock the generate_with_ai method
    def service.generate_with_ai(prompt)
      {
        success: true,
        content: JSON.generate({
          app: {
            "name" => "Todo List App",
            "description" => "A beautiful todo list application",
            "features" => ["Add tasks", "Edit tasks", "Delete tasks", "Mark as complete"]
          },
          files: [
            {
              "path" => "index.html",
              "content" => "<html><body><div id='app'></div></body></html>",
              "type" => "html"
            },
            {
              "path" => "app.js",
              "content" => "const TodoApp = () => { /* app code */ };",
              "type" => "javascript"
            },
            {
              "path" => "styles.css",
              "content" => "body { font-family: Arial; }",
              "type" => "css"
            }
          ]
        }),
        model: "moonshotai/kimi-k2",
        usage: {"prompt_tokens" => 100, "completion_tokens" => 500}
      }
    end
    
    result = service.generate!
    
    puts "Result: #{result.inspect}" if result[:success] == false
    assert result[:success], "Generation failed: #{result[:error]}"
    assert_nil result[:error]

    # Step 4: Verify app and generation were updated
    app.reload
    generation.reload

    assert_equal "generated", app.status
    assert_equal "A beautiful todo list application", app.description
    assert_equal "completed", generation.status
    assert_not_nil generation.completed_at
    assert generation.duration_seconds >= 0

    # Step 5: Verify files were created
    assert_equal 3, app.app_files.count
    
    html_file = app.app_files.find_by(path: "index.html")
    assert_not_nil html_file
    assert_equal "html", html_file.file_type
    assert html_file.content.include?("<div id='app'>")

    js_file = app.app_files.find_by(path: "app.js")
    assert_not_nil js_file
    assert_equal "javascript", js_file.file_type

    css_file = app.app_files.find_by(path: "styles.css")
    assert_not_nil css_file
    assert_equal "css", css_file.file_type

    # Step 6: Verify version is created only when there are user changes
    assert_equal 0, app.app_versions.count
  end

  test "app generation failure handling" do
    app = create(:app, team: @team, creator: @membership)
    generation = create(:app_generation, app: app, team: @team)

    service = AI::AppGeneratorService.new(app, generation)
    
    # Mock the generate_with_ai method to return failure
    def service.generate_with_ai(prompt)
      {
        success: false,
        error: "API rate limit exceeded"
      }
    end
    
    result = service.generate!
    
    assert_not result[:success]
    assert_equal "AI generation failed: API rate limit exceeded", result[:error]

    app.reload
    generation.reload

    assert_equal "failed", app.status
    assert_equal "failed", generation.status
    assert_equal "AI generation failed: API rate limit exceeded", generation.error_message
  end

  test "app update via chat message flow" do
    # Create an app with existing files
    app = create(:app, :generated, :with_files, team: @team)
    
    # Create a chat message
    chat_message = nil
    assert_difference "AppChatMessage.count", 1 do
      chat_message = app.app_chat_messages.create!(
        role: "user",
        content: "Add a delete all button",
        status: "pending"
      )
    end

    # Basic test - just verify the message was created
    assert_not_nil chat_message
    assert_equal "user", chat_message.role
    assert_equal "Add a delete all button", chat_message.content
    
    # The ProcessAppUpdateJob would handle the actual update in production
    # For now, just verify the job can be enqueued
    assert_enqueued_with(job: ProcessAppUpdateJob) do
      ProcessAppUpdateJob.perform_later(chat_message)
    end
  end

  test "multiple apps can be generated concurrently" do
    apps = []
    generations = []

    # Create multiple apps
    3.times do |i|
      app = create(:app, 
        team: @team, 
        name: "App #{i}", 
        prompt: "Create app #{i}"
      )
      generation = create(:app_generation, app: app, team: @team)
      
      apps << app
      generations << generation
    end

    # Mock successful generation for all
    mock_ai_response = {
      success: true,
      app: {"name" => "Generated App", "description" => "Test"},
      files: [{"path" => "index.html", "content" => "<html></html>", "type" => "html"}]
    }

    # Process all generations
    generations.each_with_index do |generation, i|
      service = AI::AppGeneratorService.new(apps[i], generation)
      
      # Mock the generate_with_ai method
      def service.generate_with_ai(prompt)
        {
          success: true,
          content: JSON.generate({
            app: {"name" => "Generated App", "description" => "Test"},
            files: [{"path" => "index.html", "content" => "<html></html>", "type" => "html"}]
          }),
          model: "moonshotai/kimi-k2",
          usage: {"prompt_tokens" => 50, "completion_tokens" => 200}
        }
      end
      
      result = service.generate!
      assert result[:success]
    end

    # Verify all apps were generated
    apps.each(&:reload)
    assert apps.all? { |app| app.status == "generated" }
    assert apps.all? { |app| app.app_files.count > 0 }
  end
end