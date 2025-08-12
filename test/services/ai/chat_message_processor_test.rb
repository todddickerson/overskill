require 'test_helper'

class Ai::ChatMessageProcessorTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(
      email: "test-#{Time.current.to_i}@example.com",
      password: "SecureTestPassword123!"
    )
    
    @team = Team.create!(name: "Test Team #{Time.current.to_i}")
    
    @membership = @team.memberships.create!(
      user: @user,
      role_ids: ['admin']
    )
    
    @app = App.create!(
      name: "Test App #{Time.current.to_i}",
      slug: "test-app-#{Time.current.to_i}",
      team: @team,
      creator: @membership,
      prompt: "Test app prompt"
    )
  end
  
  test "classifies add feature messages correctly" do
    message = create_message("Add user authentication to the app")
    processor = Ai::ChatMessageProcessor.new(message)
    
    analysis = processor.send(:classify_message_intent)
    
    assert_equal :add_feature, analysis[:type]
    assert_includes analysis[:entities][:features], 'authentication'
    assert_operator analysis[:confidence], :>, 0.5
  end
  
  test "classifies modify feature messages correctly" do
    message = create_message("Change the button color to blue")
    processor = Ai::ChatMessageProcessor.new(message)
    
    analysis = processor.send(:classify_message_intent)
    
    assert_equal :style_change, analysis[:type]
    assert_includes analysis[:entities][:colors], 'blue'
    assert_includes analysis[:entities][:ui_elements], 'button'
  end
  
  test "classifies fix bug messages correctly" do
    message = create_message("Fix the login form validation error")
    processor = Ai::ChatMessageProcessor.new(message)
    
    analysis = processor.send(:classify_message_intent)
    
    assert_equal :fix_bug, analysis[:type]
    assert_includes analysis[:entities][:features], 'login'
    assert_includes analysis[:entities][:ui_elements], 'form'
  end
  
  test "classifies questions correctly" do
    message = create_message("How do I deploy this app?")
    processor = Ai::ChatMessageProcessor.new(message)
    
    analysis = processor.send(:classify_message_intent)
    
    assert_equal :question, analysis[:type]
  end
  
  test "extracts entities from complex messages" do
    message = create_message("Add a red button component with authentication features")
    processor = Ai::ChatMessageProcessor.new(message)
    
    analysis = processor.send(:classify_message_intent)
    
    assert_includes analysis[:entities][:colors], 'red'
    assert_includes analysis[:entities][:ui_elements], 'button'
    assert_includes analysis[:entities][:features], 'authentication'
  end
  
  test "determines change scope correctly" do
    processor_major = Ai::ChatMessageProcessor.new(create_message("Rebuild the entire app with new features"))
    processor_minor = Ai::ChatMessageProcessor.new(create_message("Change button color"))
    
    major_analysis = processor_major.send(:classify_message_intent)
    minor_analysis = processor_minor.send(:classify_message_intent)
    
    assert_equal :major, major_analysis[:scope]
    assert_equal :minor, minor_analysis[:scope]
  end
  
  test "processes message without external API calls" do
    message = create_message("Add a simple todo component")
    processor = Ai::ChatMessageProcessor.new(message)
    
    # Mock the external dependencies to avoid API calls
    processor.stubs(:analyze_current_app_state).returns({
      file_structure: { total_files: 5 },
      existing_components: {},
      dependencies: {}
    })
    
    processor.stubs(:generate_action_plan).returns({
      type: :feature_addition,
      steps: [],
      summary: "Test plan"
    })
    
    processor.stubs(:execute_changes).returns({
      success: true,
      files_changed: [],
      step_results: []
    })
    
    processor.stubs(:update_live_preview).returns({
      success: true,
      preview_url: "https://test.example.com"
    })
    
    result = processor.process!
    
    assert result[:success]
    assert_match(/Test plan/, result[:message])
  end
  
  test "handles processing errors gracefully" do
    message = create_message("This message will cause an error")
    processor = Ai::ChatMessageProcessor.new(message)
    
    # Force an error during processing
    processor.stubs(:analyze_current_app_state).raises(StandardError, "Test error")
    
    result = processor.process!
    
    assert_not result[:success]
    assert_includes result[:message], "error"
    
    # Should create an error response message
    error_messages = @app.app_chat_messages.where(role: 'assistant')
    assert_operator error_messages.count, :>, 0
  end
  
  test "builds conversation context" do
    # Create some existing messages
    @app.app_chat_messages.create!(
      content: "Previous message 1",
      user: @user,
      role: 'user'
    )
    
    @app.app_chat_messages.create!(
      content: "Previous message 2", 
      user: @user,
      role: 'user'
    )
    
    message = create_message("Current message")
    processor = Ai::ChatMessageProcessor.new(message)
    
    context = processor.send(:build_conversation_context)
    
    assert context[:recent_messages].present?
    assert_equal 'generated', context[:app_status]
    assert context[:user_patterns].present?
  end
  
  test "analyzes user communication patterns" do
    # Create messages with different patterns
    %w[
      "Add authentication"
      "Change button color" 
      "Fix login bug"
      "Add todo feature"
    ].each do |content|
      @app.app_chat_messages.create!(
        content: content,
        user: @user,
        role: 'user'
      )
    end
    
    message = create_message("New message")
    processor = Ai::ChatMessageProcessor.new(message)
    
    patterns = processor.send(:analyze_user_communication_patterns)
    
    assert patterns[:total_messages] > 0
    assert patterns[:common_request_types].present?
  end
  
  test "executes step modifications safely" do
    # Create a test file
    @app.app_files.create!(
      path: 'src/test.tsx',
      content: 'export default function Test() { return <div>original</div>; }',
      team: @team
    )
    
    message = create_message("Update the test component")
    processor = Ai::ChatMessageProcessor.new(message)
    
    step = {
      action: :modify_files,
      files: [
        {
          path: 'src/test.tsx',
          changes: {
            type: :content_replacement,
            find: 'original',
            replace: 'updated'
          }
        }
      ]
    }
    
    result = processor.send(:execute_step, step)
    
    assert result[:success]
    assert_includes result[:files_changed], 'src/test.tsx'
    
    # Verify file was updated
    file = @app.app_files.find_by(path: 'src/test.tsx')
    assert_includes file.content, 'updated'
  end
  
  test "executes dependency additions" do
    # Ensure app has package.json
    package_content = {
      "name" => "test-app",
      "dependencies" => {
        "react" => "^18.0.0"
      }
    }.to_json
    
    @app.app_files.create!(
      path: 'package.json',
      content: package_content,
      team: @team
    )
    
    message = create_message("Add new packages")
    processor = Ai::ChatMessageProcessor.new(message)
    
    step = {
      action: :add_dependencies,
      packages: ['lodash', 'axios']
    }
    
    result = processor.send(:execute_step, step)
    
    assert result[:success]
    assert_equal 2, result[:packages_added].count
    
    # Verify package.json was updated
    package_file = @app.app_files.find_by(path: 'package.json')
    package_data = JSON.parse(package_file.content)
    assert package_data['dependencies']['lodash'].present?
    assert package_data['dependencies']['axios'].present?
  end
  
  private
  
  def create_message(content)
    @app.app_chat_messages.create!(
      content: content,
      user: @user,
      role: 'user'
    )
  end
end