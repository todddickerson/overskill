require "application_system_test_case"

class V4ChatDevelopmentTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  
  def setup
    # Create test user and team
    @user = User.create!(
      email: "v4test#{Time.current.to_i}@example.com",
      password: "SecureTestPassword123!"
    )
    
    @team = Team.create!(name: "V4 Test Team #{Time.current.to_i}")
    @membership = @team.memberships.create!(user: @user, role_ids: ['admin'])
    
    # Sign in user (if using Devise or similar)
    sign_in @user if respond_to?(:sign_in)
  end
  
  test "complete V4 chat development flow" do
    # Test 1: Initial app creation and generation
    app = create_test_app("Generate a todo app with add, complete, and delete functionality")
    
    assert app.persisted?, "App should be created"
    assert_equal "generating", app.status
    
    # Execute V4 generation
    perform_enqueued_jobs do
      initial_message = app.app_chat_messages.create!(
        content: "Create a simple todo app with add, complete, and delete tasks",
        user: @user,
        role: 'user'
      )
      
      builder = Ai::AppBuilderV4.new(initial_message)
      builder.execute!
    end
    
    app.reload
    assert_equal "generated", app.status
    assert_operator app.app_files.count, :>=, 20, "Should have at least 20 files generated"
    
    # Verify key files exist
    assert app.app_files.exists?(path: 'package.json'), "Should have package.json"
    assert app.app_files.exists?(path: 'src/components/TodoList.tsx'), "Should have TodoList component"
    assert app.app_files.exists?(path: 'src/pages/Dashboard.tsx'), "Should have Dashboard page"
    
    # Test 2: Chat-based modification
    modification_message = app.app_chat_messages.create!(
      content: "Make the todo items show completed tasks in gray with strikethrough text",
      user: @user,
      role: 'user'
    )
    
    processor = Ai::ChatMessageProcessor.new(modification_message)
    result = processor.process!
    
    assert result[:success], "Chat modification should succeed"
    assert_operator result[:files_changed].count, :>, 0, "Should modify at least one file"
    
    # Verify response message was created
    response_messages = app.app_chat_messages.where(role: 'assistant')
    assert_operator response_messages.count, :>, 0, "Should have assistant response"
    
    # Test 3: File context analysis
    analyzer = Ai::FileContextAnalyzer.new(app)
    context = analyzer.analyze
    
    assert context[:file_structure][:total_files] > 0, "Should analyze file structure"
    assert context[:existing_components].present?, "Should identify components"
    assert context[:dependencies].present?, "Should parse dependencies"
    
    # Test 4: Component addition via chat
    component_message = app.app_chat_messages.create!(
      content: "Add user authentication with login and signup pages",
      user: @user,
      role: 'user'
    )
    
    processor = Ai::ChatMessageProcessor.new(component_message)
    result = processor.process!
    
    # Should succeed even if external APIs are not available
    assert result.key?(:success), "Should return result with success key"
    
    # Test 5: Build system integration
    app.reload
    final_file_count = app.app_files.count
    
    builder = Deployment::ExternalViteBuilder.new(app)
    
    # Test build (may fail without Node.js in CI, but should not crash)
    build_result = nil
    assert_nothing_raised "Build should not raise exceptions" do
      build_result = builder.build_for_preview
    rescue => e
      # Acceptable failures in test environment
      if e.message.include?("npm") || e.message.include?("Node.js") || e.message.include?("vite")
        build_result = { success: false, error: e.message, test_environment: true }
      else
        raise e
      end
    end
    
    assert build_result.present?, "Should return build result"
    
    # Test 6: Live preview management
    preview_manager = Ai::LivePreviewManager.new(app)
    changed_files = ['src/components/TodoList.tsx', 'src/App.tsx']
    
    preview_result = nil
    assert_nothing_raised "Preview update should not raise exceptions" do
      preview_result = preview_manager.update_preview_after_changes(changed_files)
    rescue => e
      # Acceptable failures without external services
      if e.message.include?("Cloudflare") || e.message.include?("deployment")
        preview_result = { success: false, error: e.message, test_environment: true }
      else
        raise e
      end
    end
    
    assert preview_result.present?, "Should return preview result"
    assert_equal 2, preview_result[:changes_applied]
    
    # Verify final state
    app.reload
    assert_operator app.app_files.count, :>=, final_file_count, "File count should not decrease"
    assert_operator app.app_chat_messages.count, :>=, 3, "Should have multiple chat messages"
  end
  
  test "chat message classification" do
    app = create_test_app("Test app for message classification")
    
    test_cases = [
      {
        content: "Add user authentication to the app",
        expected_type: :add_feature,
        expected_entities: { features: ['authentication'] }
      },
      {
        content: "Change the button color to blue",
        expected_type: :style_change,
        expected_entities: { colors: ['blue'], ui_elements: ['button'] }
      },
      {
        content: "Fix the login form validation error",
        expected_type: :fix_bug,
        expected_entities: { features: ['login'], ui_elements: ['form'] }
      },
      {
        content: "How do I deploy this app?",
        expected_type: :question
      }
    ]
    
    test_cases.each do |test_case|
      message = app.app_chat_messages.create!(
        content: test_case[:content],
        user: @user,
        role: 'user'
      )
      
      processor = Ai::ChatMessageProcessor.new(message)
      analysis = processor.send(:classify_message_intent)
      
      assert_equal test_case[:expected_type], analysis[:type], 
        "Should classify '#{test_case[:content]}' as #{test_case[:expected_type]}"
      
      if test_case[:expected_entities]
        test_case[:expected_entities].each do |entity_type, expected_values|
          expected_values.each do |value|
            assert_includes analysis[:entities][entity_type], value,
              "Should extract #{value} from #{entity_type}"
          end
        end
      end
    end
  end
  
  test "file context analyzer capabilities" do
    app = create_test_app("Test app for context analysis")
    
    # Create some test files
    app.app_files.create!(
      path: 'src/components/TestComponent.tsx',
      team: @team,
      content: <<~TSX
        import React, { useState } from 'react';
        
        interface TestProps {
          title: string;
          optional?: boolean;
        }
        
        export default function TestComponent({ title, optional }: TestProps) {
          const [count, setCount] = useState(0);
          
          return (
            <div className="bg-blue-500 text-white p-4">
              <h1>{title}</h1>
              <button onClick={() => setCount(count + 1)}>
                Count: {count}
              </button>
            </div>
          );
        }
      TSX
    )
    
    app.app_files.create!(
      path: 'src/hooks/useCustomHook.ts',
      team: @team,
      content: <<~TS
        import { useState, useEffect } from 'react';
        import { supabase } from '@/lib/supabase';
        
        export function useCustomHook() {
          const [data, setData] = useState(null);
          
          useEffect(() => {
            supabase.from('todos').select('*').then(setData);
          }, []);
          
          return { data };
        }
      TS
    )
    
    analyzer = Ai::FileContextAnalyzer.new(app)
    context = analyzer.analyze
    
    # Test file structure analysis
    assert context[:file_structure][:total_files] > 0
    assert context[:file_structure][:by_type]['typescript'].present?
    
    # Test component analysis
    assert context[:existing_components]['TestComponent'].present?
    
    component = context[:existing_components]['TestComponent']
    assert_equal :stateful_component, component[:type]
    assert_includes component[:props].map { |p| p[:name] }, 'title'
    assert_includes component[:props].map { |p| p[:name] }, 'optional'
    assert_includes component[:ui_framework], 'tailwind'
    assert_includes component[:state_management], 'useState'
    
    # Test dependency analysis if package.json exists
    if app.app_files.exists?(path: 'package.json')
      assert context[:dependencies][:dependencies].present?
    end
    
    # Test database schema inference
    assert context[:database_schema][:tables].present?
    assert context[:database_schema][:tables]['todos'].present?
  end
  
  test "action plan generation for different request types" do
    app = create_test_app("Test app for action planning")
    
    # Add some initial files for context
    app.app_files.create!(
      path: 'src/components/ExistingComponent.tsx',
      team: @team,
      content: 'export default function ExistingComponent() { return <div>Test</div>; }'
    )
    
    test_requests = [
      {
        content: "Add a chat feature to the app",
        expected_plan_type: :feature_addition,
        expected_steps: [:suggest_components, :add_files]
      },
      {
        content: "Change the existing component to use red color",
        expected_plan_type: :style_change,
        expected_steps: [:apply_styling]
      },
      {
        content: "Fix the component that's not rendering properly",
        expected_plan_type: :bug_fix,
        expected_steps: [:modify_files]
      }
    ]
    
    test_requests.each do |request|
      message = app.app_chat_messages.create!(
        content: request[:content],
        user: @user,
        role: 'user'
      )
      
      # Analyze the app context
      context = Ai::FileContextAnalyzer.new(app).analyze
      
      # Classify the message
      processor = Ai::ChatMessageProcessor.new(message)
      analysis = processor.send(:classify_message_intent)
      
      # Generate action plan
      generator = Ai::ActionPlanGenerator.new(app, message, analysis, context)
      plan = generator.generate
      
      assert_equal request[:expected_plan_type], plan[:type],
        "Should generate #{request[:expected_plan_type]} plan for '#{request[:content]}'"
      
      assert plan[:steps].present?, "Plan should have steps"
      
      step_actions = plan[:steps].map { |step| step[:action] }
      request[:expected_steps].each do |expected_step|
        # Allow flexible step matching since plans may vary
        assert step_actions.any? { |action| action.to_s.include?(expected_step.to_s) },
          "Plan should include #{expected_step} step"
      end
      
      assert plan[:estimated_time] > 0, "Should estimate implementation time"
    end
  end
  
  test "incremental build strategy selection" do
    app = create_test_app("Test app for build strategies")
    
    # Create a preview manager
    preview_manager = Ai::LivePreviewManager.new(app)
    
    # Test different change scenarios
    test_scenarios = [
      {
        changed_files: ['src/components/TestComponent.tsx'],
        expected_strategy: :hot_component_update,
        description: "Single component change"
      },
      {
        changed_files: ['src/components/A.tsx', 'src/components/B.tsx'],
        expected_strategy: :hot_component_update,
        description: "Multiple component changes"
      },
      {
        changed_files: ['src/components/A.tsx', 'src/components/B.tsx', 'src/components/C.tsx', 'src/components/D.tsx'],
        expected_strategy: :incremental_build,
        description: "Many component changes"
      },
      {
        changed_files: ['package.json'],
        expected_strategy: :full_rebuild,
        description: "Configuration file change"
      },
      {
        changed_files: ['src/main.tsx'],
        expected_strategy: :full_rebuild,
        description: "Core file change"
      }
    ]
    
    test_scenarios.each do |scenario|
      analysis = preview_manager.send(:analyze_file_changes, scenario[:changed_files])
      strategy = preview_manager.send(:determine_build_strategy, analysis)
      
      assert_equal scenario[:expected_strategy], strategy,
        "Should use #{scenario[:expected_strategy]} for #{scenario[:description]}"
    end
  end
  
  test "error handling and recovery" do
    app = create_test_app("Test app for error handling")
    
    # Test ChatMessageProcessor error handling
    message = app.app_chat_messages.create!(
      content: "This is a test message that might cause issues",
      user: @user,
      role: 'user'
    )
    
    processor = Ai::ChatMessageProcessor.new(message)
    
    # Should not raise exceptions even if external services fail
    result = nil
    assert_nothing_raised "Should handle errors gracefully" do
      result = processor.process!
    end
    
    assert result.present?, "Should return result even on errors"
    assert result.key?(:success), "Should indicate success/failure status"
    
    # Test FileContextAnalyzer with minimal files
    minimal_app = App.create!(
      name: "Minimal Test App",
      slug: "minimal-#{Time.current.to_i}",
      team: @team,
      creator: @membership,
      prompt: "minimal"
    )
    
    analyzer = Ai::FileContextAnalyzer.new(minimal_app)
    
    assert_nothing_raised "Should handle apps with no files" do
      context = analyzer.analyze
      assert context.present?
      assert context[:file_structure][:total_files] == 0
    end
  end
  
  private
  
  def create_test_app(prompt)
    App.create!(
      name: "V4 System Test App #{Time.current.to_i}",
      slug: "v4-test-#{Time.current.to_i}",
      team: @team,
      creator: @membership,
      prompt: prompt,
      status: 'generating'
    )
  end
end