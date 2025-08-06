require 'test_helper'

class UnifiedAiCoordinatorTest < ActiveSupport::TestCase
  setup do
    @team = teams(:one)
    @user = users(:one)
    @app = apps(:one)
    @message = @app.app_chat_messages.create!(
      role: "user",
      content: "Add a contact form to my landing page",
      user: @user
    )
  end
  
  test "coordinator initializes with app and message" do
    coordinator = Ai::UnifiedAiCoordinator.new(@app, @message)
    assert_equal @app, coordinator.app
    assert_equal @message, coordinator.message
    assert_not_nil coordinator.todo_tracker
    assert_not_nil coordinator.progress_broadcaster
  end
  
  test "coordinator routes generation request correctly" do
    generation_message = @app.app_chat_messages.create!(
      role: "user",
      content: "Create a new landing page with hero section and pricing",
      user: @user
    )
    
    coordinator = Ai::UnifiedAiCoordinator.new(@app, generation_message)
    
    # Mock the router to test routing logic
    router_mock = Minitest::Mock.new
    router_mock.expect :route, { action: :generate }
    router_mock.expect :extract_metadata, { wants_deployment: false }
    
    Ai::Services::MessageRouter.stub :new, router_mock do
      # Mock the generation method
      coordinator.stub :generate_new_app, true do
        coordinator.execute!
      end
    end
    
    router_mock.verify
  end
  
  test "coordinator routes update request correctly" do
    update_message = @app.app_chat_messages.create!(
      role: "user", 
      content: "Change the button color to blue",
      user: @user
    )
    
    coordinator = Ai::UnifiedAiCoordinator.new(@app, update_message)
    
    # Mock the router to test routing logic
    router_mock = Minitest::Mock.new
    router_mock.expect :route, { action: :update }
    router_mock.expect :extract_metadata, { wants_deployment: true }
    
    Ai::Services::MessageRouter.stub :new, router_mock do
      # Mock the update method
      coordinator.stub :update_existing_app, true do
        coordinator.execute!
      end
    end
    
    router_mock.verify
  end
  
  test "coordinator handles errors gracefully" do
    coordinator = Ai::UnifiedAiCoordinator.new(@app, @message)
    
    # Force an error in routing
    Ai::Services::MessageRouter.stub :new, ->(_) { raise StandardError.new("Test error") } do
      # Should not raise, but handle error internally
      assert_nothing_raised do
        coordinator.execute!
      end
    end
  end
  
  test "coordinator creates version after successful generation" do
    coordinator = Ai::UnifiedAiCoordinator.new(@app, @message)
    
    initial_version_count = @app.app_versions.count
    
    # Mock successful file creation
    files = [
      { path: "index.html", content: "<html>Test</html>" },
      { path: "style.css", content: "body { color: blue; }" }
    ]
    
    coordinator.stub :analyze_requirements, { "files_to_create" => ["index.html", "style.css"] } do
      coordinator.stub :generate_file_content, "<html>Test</html>" do
        coordinator.stub :create_generation_plan, { files: files } do
          coordinator.stub :review_and_optimize, files do
            # This would normally be called via execute!
            coordinator.send(:save_files, files)
            coordinator.send(:create_version)
          end
        end
      end
    end
    
    assert_equal initial_version_count + 1, @app.app_versions.count
    assert_equal "1.0.0", @app.app_versions.last.version_number
  end
  
  test "next version number increments correctly" do
    coordinator = Ai::UnifiedAiCoordinator.new(@app, @message)
    
    # Create initial version
    @app.app_versions.create!(
      team: @team,
      user: @user,
      version_number: "1.0.5",
      changelog: "Test version"
    )
    
    assert_equal "1.0.6", coordinator.send(:next_version_number)
  end
  
  test "detect file type works correctly" do
    coordinator = Ai::UnifiedAiCoordinator.new(@app, @message)
    
    assert_equal 'html', coordinator.send(:detect_file_type, 'index.html')
    assert_equal 'js', coordinator.send(:detect_file_type, 'app.js')
    assert_equal 'css', coordinator.send(:detect_file_type, 'style.css')
    assert_equal 'json', coordinator.send(:detect_file_type, 'config.json')
    assert_equal 'text', coordinator.send(:detect_file_type, 'readme.txt')
  end
  
  test "parse json response handles various formats" do
    coordinator = Ai::UnifiedAiCoordinator.new(@app, @message)
    
    # Test with markdown code block
    content_with_markdown = '```json
    {"test": "value"}
    ```'
    result = coordinator.send(:parse_json_response, content_with_markdown)
    assert_equal "value", result["test"]
    
    # Test with raw JSON
    raw_json = '{"another": "test"}'
    result = coordinator.send(:parse_json_response, raw_json)
    assert_equal "test", result["another"]
    
    # Test with invalid JSON
    invalid = 'not json at all'
    result = coordinator.send(:parse_json_response, invalid)
    assert_equal({}, result)
  end
end