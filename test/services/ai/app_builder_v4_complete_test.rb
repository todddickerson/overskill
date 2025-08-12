require 'test_helper'

class Ai::AppBuilderV4CompleteTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @team = teams(:one)
    @app = apps(:one)
    
    # Create initial message
    @message = @app.app_chat_messages.create!(
      role: 'user',
      content: 'Build a todo app with user authentication',
      user: @user
    )
    
    @builder = Ai::AppBuilderV4.new(@message)
  end

  test "initializes with message and creates version" do
    assert_equal @app, @builder.instance_variable_get(:@app)
    assert_equal @message, @builder.instance_variable_get(:@message)
    assert_not_nil @builder.instance_variable_get(:@app_version)
  end

  test "execute_generation! runs all phases" do
    # Mock the individual phases to track execution
    phases_executed = []
    
    @builder.stub :generate_shared_foundation, -> { phases_executed << :foundation } do
      @builder.stub :generate_component_context, "component context" do
        @builder.stub :generate_app_features_with_components, -> (_) { phases_executed << :features } do
          @builder.stub :integrate_requested_components, -> { phases_executed << :components } do
            @builder.stub :apply_smart_edits, -> { phases_executed << :edits } do
              @builder.stub :build_for_deployment, { success: true } do
                @builder.send(:execute_generation!)
              end
            end
          end
        end
      end
    end
    
    assert_includes phases_executed, :foundation
    assert_includes phases_executed, :features
    assert_includes phases_executed, :components
    assert_includes phases_executed, :edits
    assert_equal 'generated', @app.reload.status
  end

  test "generate_app_features_with_components builds proper prompt" do
    component_context = "Available components: Button, Card, Input"
    
    @builder.stub :generate_with_claude_conversation, nil do
      @builder.generate_app_features_with_components(component_context)
    end
    
    # Verify prompt building was called
    prompt = @builder.send(:build_generation_prompt, component_context)
    
    assert_includes prompt, @app.name
    assert_includes prompt, @message.content
    assert_includes prompt, component_context
    assert_includes prompt, "TypeScript and React"
    assert_includes prompt, "app-scoped database"
  end

  test "plan_files_needed determines correct files for todo app" do
    files = @builder.send(:plan_files_needed)
    
    assert_includes files, 'src/pages/Dashboard.tsx'
    assert_includes files, 'src/components/TodoList.tsx'
    assert_includes files, 'src/components/TodoItem.tsx'
    assert_includes files, 'src/hooks/useTodos.ts'
    assert_includes files, 'src/types/app.ts'
    assert_includes files, 'src/lib/app-utils.ts'
  end

  test "plan_files_needed determines correct files for chat app" do
    @message.update!(content: 'Build a chat application')
    files = @builder.send(:plan_files_needed)
    
    assert_includes files, 'src/components/ChatInterface.tsx'
    assert_includes files, 'src/components/MessageList.tsx'
    assert_includes files, 'src/hooks/useChat.ts'
  end

  test "generate_with_claude_conversation batches files correctly" do
    batches_processed = []
    
    @builder.stub :plan_files_needed, ['file1.tsx', 'file2.tsx', 'file3.tsx', 'file4.tsx'] do
      @builder.stub :generate_files_with_claude, ->(prompt, batch) { 
        batches_processed << batch
        { success: true, files: batch }
      } do
        @builder.send(:generate_with_claude_conversation, "test prompt")
      end
    end
    
    # Should batch into groups of 2
    assert_equal 2, batches_processed.size
    assert_equal ['file1.tsx', 'file2.tsx'], batches_processed[0]
    assert_equal ['file3.tsx', 'file4.tsx'], batches_processed[1]
  end

  test "integrate_requested_components analyzes and integrates components" do
    # Create a file that references Button component
    @app.app_files.create!(
      path: 'src/pages/Dashboard.tsx',
      content: 'import { Button } from "@/components/ui/button"',
      team: @team
    )
    
    components = @builder.send(:analyze_component_requirements)
    assert_includes components, 'button'
    
    # Test integration
    @builder.stub :integrate_component, nil do
      @builder.integrate_requested_components
    end
  end

  test "apply_smart_edits uses SmartSearchService" do
    # Create a file with TODO
    todo_file = @app.app_files.create!(
      path: 'src/components/Test.tsx',
      content: '// TODO: Implement this component',
      team: @team
    )
    
    # Mock search results
    search_results = {
      success: true,
      results: [{
        file: todo_file,
        line_number: 1,
        match: '// TODO: Implement this component'
      }]
    }
    
    Ai::SmartSearchService.any_instance.stub :search_files, search_results do
      @builder.apply_smart_edits
    end
  end

  test "create_app_file creates new file when not exists" do
    assert_difference '@app.app_files.count', 1 do
      @builder.send(:create_app_file, 'test.tsx', 'content')
    end
    
    file = @app.app_files.find_by(path: 'test.tsx')
    assert_not_nil file
    assert_equal 'content', file.content
    assert_equal @team, file.team
  end

  test "create_app_file updates existing file" do
    existing = @app.app_files.create!(
      path: 'existing.tsx',
      content: 'old content',
      team: @team
    )
    
    assert_no_difference '@app.app_files.count' do
      @builder.send(:create_app_file, 'existing.tsx', 'new content')
    end
    
    existing.reload
    assert_equal 'new content', existing.content
  end

  test "generate_placeholder_content creates appropriate Dashboard content" do
    content = @builder.send(:generate_placeholder_content, 'src/pages/Dashboard.tsx')
    
    assert_includes content, 'import React'
    assert_includes content, 'useAuth'
    assert_includes content, 'app-scoped-db'
    assert_includes content, 'export default function Dashboard'
  end

  test "generate_placeholder_content creates appropriate component content" do
    content = @builder.send(:generate_placeholder_content, 'src/components/TodoList.tsx')
    
    assert_includes content, 'import React'
    assert_includes content, 'export default function TodoList'
  end

  test "generate_placeholder_content creates appropriate hook content" do
    content = @builder.send(:generate_placeholder_content, 'src/hooks/useTodos.ts')
    
    assert_includes content, 'export function useTodos'
  end

  test "process_template_variables replaces all variables" do
    template = "Welcome to {{APP_NAME}} (ID: {{APP_ID}}, Slug: {{APP_SLUG}})"
    processed = @builder.send(:process_template_variables, template)
    
    assert_includes processed, @app.name
    assert_includes processed, @app.id.to_s
    assert_includes processed, @app.name.parameterize
    assert_not_includes processed, '{{'
  end

  test "determine_component_path returns correct paths" do
    assert_equal 'src/components/auth/login', 
                 @builder.send(:determine_component_path, 'auth/login')
    
    assert_equal 'src/hooks/infinite-query', 
                 @builder.send(:determine_component_path, 'data/infinite-query')
    
    assert_equal 'src/components/realtime/chat', 
                 @builder.send(:determine_component_path, 'realtime/chat')
    
    assert_equal 'src/components/ui/button.tsx', 
                 @builder.send(:determine_component_path, 'button')
  end

  test "build_batch_prompt includes previous files" do
    base_prompt = "Generate app files"
    batch = ['file3.tsx', 'file4.tsx']
    files_created = ['file1.tsx', 'file2.tsx']
    
    prompt = @builder.send(:build_batch_prompt, base_prompt, batch, files_created)
    
    assert_includes prompt, base_prompt
    assert_includes prompt, "Files already created:"
    assert_includes prompt, "file1.tsx"
    assert_includes prompt, "file2.tsx"
    assert_includes prompt, "Now create these files:"
    assert_includes prompt, "file3.tsx"
    assert_includes prompt, "file4.tsx"
  end

  test "error recovery creates proper message" do
    error = StandardError.new("Test error")
    
    @builder.send(:create_error_recovery_message, error, 1)
    
    recovery_message = @app.app_chat_messages.last
    assert_equal 'user', recovery_message.role
    assert_equal @user, recovery_message.user
    assert_includes recovery_message.content, "Test error"
    assert_includes recovery_message.content, "attempt 1"
    
    metadata = JSON.parse(recovery_message.metadata)
    assert_equal 'error_recovery', metadata['type']
    assert_equal 1, metadata['attempt']
    assert metadata['billing_ignore']
  end

  test "execute_with_retry handles errors with recovery" do
    attempt_count = 0
    
    @builder.stub :execute_generation!, -> {
      attempt_count += 1
      raise "Test error" if attempt_count == 1
      # Succeed on second attempt
    } do
      @builder.stub :create_error_recovery_message, nil do
        @builder.stub :sleep, nil do
          @builder.send(:execute_with_retry)
        end
      end
    end
    
    assert_equal 2, attempt_count
  end

  test "execute_with_retry fails after max retries" do
    @builder.stub :execute_generation!, -> { raise "Persistent error" } do
      @builder.stub :create_error_recovery_message, nil do
        @builder.stub :sleep, nil do
          assert_raises StandardError do
            @builder.send(:execute_with_retry)
          end
        end
      end
    end
    
    assert_equal 'failed', @app.reload.status
  end
end