require 'test_helper'

class Ai::StreamingToolExecutorTest < ActiveSupport::TestCase
  setup do
    # Create test data directly like AppBuilderV5Test does
    @user = User.create!(
      email: "test_streaming@example.com",
      password: "password123",
      time_zone: "UTC"
    )
    @team = Team.create!(
      name: "Test Streaming Team"
    )
    @membership = @team.memberships.create!(user: @user)
    
    @app = App.create!(
      name: "Test Streaming App",
      team: @team,
      creator: @membership,
      description: "Test app for streaming tool executor",
      prompt: "Test streaming"
    )
    
    @message = @app.app_chat_messages.create!(
      role: 'assistant',
      content: 'Testing tool streaming',
      user: @user,
      conversation_flow: [],
      tool_calls: []
    )
    @executor = Ai::StreamingToolExecutor.new(@message, @app, 1)
  end

  test "execute_with_streaming updates tool status to running" do
    tool_call = {
      'name' => 'os-write',
      'arguments' => {
        'file_path' => 'test.js',
        'content' => 'console.log("test");'
      }
    }
    
    # Add initial tool to conversation_flow
    @message.conversation_flow = [
      {
        'type' => 'tools',
        'calls' => [
          {
            'name' => 'os-write',
            'file_path' => 'test.js',
            'status' => 'pending'
          }
        ]
      }
    ]
    @message.save!
    
    # Mock broadcasting
    mock_broadcast = Minitest::Mock.new
    mock_broadcast.expect :broadcast_replace_to, nil, [String, Hash]
    
    Turbo::StreamsChannel.stub :broadcast_replace_to, mock_broadcast do
      result = @executor.execute_with_streaming(tool_call, 0)
      
      # Reload message to check updates
      @message.reload
      
      # Check that status was updated
      assert_includes ['running', 'complete'], @message.conversation_flow.last['calls'].first['status']
      assert result[:success] || result[:path]
    end
  end

  test "execute_with_streaming handles tool errors" do
    tool_call = {
      'name' => 'os-write',
      'arguments' => {
        'file_path' => nil, # Invalid - will cause error
        'content' => 'test'
      }
    }
    
    @message.conversation_flow = [
      {
        'type' => 'tools',
        'calls' => [
          {
            'name' => 'os-write',
            'file_path' => nil,
            'status' => 'pending'
          }
        ]
      }
    ]
    @message.save!
    
    result = @executor.execute_with_streaming(tool_call, 0)
    
    assert result[:error]
    @message.reload
    assert_equal 'error', @message.conversation_flow.last['calls'].first['status']
  end

  test "execute_with_streaming broadcasts updates via ActionCable" do
    tool_call = {
      'name' => 'os-view',
      'arguments' => {
        'file_path' => 'package.json'
      }
    }
    
    @message.conversation_flow = [
      {
        'type' => 'tools', 
        'calls' => [
          {
            'name' => 'os-view',
            'file_path' => 'package.json',
            'status' => 'pending'
          }
        ]
      }
    ]
    @message.save!
    
    broadcast_count = 0
    
    # Count broadcasts
    Turbo::StreamsChannel.stub :broadcast_replace_to, ->(*args) { broadcast_count += 1 } do
      ActionCable.server.stub :broadcast, ->(*args) { broadcast_count += 1 } do
        @executor.execute_with_streaming(tool_call, 0)
      end
    end
    
    # Should broadcast at least twice (running status + complete status)
    assert broadcast_count >= 2, "Expected at least 2 broadcasts, got #{broadcast_count}"
  end

  test "streaming executor handles different tool types" do
    tools_to_test = [
      ['os-write', { 'file_path' => 'test.txt', 'content' => 'test' }],
      ['os-line-replace', { 'file_path' => 'test.txt', 'start_line' => 1, 'end_line' => 1, 'new_content' => 'replaced' }],
      ['os-delete', { 'file_path' => 'test.txt' }],
      ['os-search', { 'query' => 'test', 'path' => '.' }],
      ['os-view', { 'file_path' => 'test.txt' }]
    ]
    
    tools_to_test.each do |tool_name, args|
      tool_call = { 'name' => tool_name, 'arguments' => args }
      
      @message.conversation_flow = [
        {
          'type' => 'tools',
          'calls' => [
            {
              'name' => tool_name,
              'file_path' => args['file_path'],
              'status' => 'pending'
            }
          ]
        }
      ]
      @message.save!
      
      # Should not raise errors
      assert_nothing_raised do
        @executor.execute_with_streaming(tool_call, 0)
      end
    end
  end
end