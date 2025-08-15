require 'test_helper'

class Ai::AppBuilderV5LineReplaceTest < ActiveSupport::TestCase
  setup do
    # Create test data without fixtures
    @user = User.create!(
      email: "test#{Time.now.to_i}@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
    @team = Team.create!(name: "Test Team #{Time.now.to_i}")
    membership = @team.memberships.create!(user: @user)
    
    @app = App.create!(
      name: "Test App", 
      team: @team,
      creator: membership,
      status: 'generating',
      prompt: 'Build a test app'
    )
    
    @chat_message = AppChatMessage.create!(
      user: @user,
      app: @app,
      content: "Build a todo app",
      role: 'user'
    )
    
    @builder = Ai::AppBuilderV5.new(@chat_message)
    
    # Create a test file
    @test_file = @app.app_files.create!(
      path: 'src/components/Button.tsx',
      team: @team,
      content: <<~TSX
        import React from 'react';
        
        const Button = () => {
          return (
            <button className="old-class">
              Click me
            </button>
          );
        };
        
        export default Button;
      TSX
    )
  end

  test "replace_file_content handles basic line replacement correctly" do
    args = {
      'file_path' => 'src/components/Button.tsx',
      'search' => '    <button className="old-class">\n      Click me\n    </button>',
      'first_replaced_line' => 5,
      'last_replaced_line' => 7,
      'replace' => '    <button className="new-class">\n      Updated text\n    </button>'
    }
    
    result = @builder.send(:replace_file_content, args)
    
    assert result[:success]
    @test_file.reload
    assert_includes @test_file.content, 'className="new-class"'
    assert_includes @test_file.content, 'Updated text'
    assert_not_includes @test_file.content, 'old-class'
  end

  test "replace_file_content handles ellipsis patterns correctly" do
    # Create a longer file with more content
    long_file = @app.app_files.create!(
      path: 'src/components/LongComponent.tsx',
      team: @team,
      content: <<~TSX
        import React from 'react';
        
        const LongComponent = () => {
          const items = [
            { id: 1, name: 'Item 1' },
            { id: 2, name: 'Item 2' },
            { id: 3, name: 'Item 3' },
            { id: 4, name: 'Item 4' },
            { id: 5, name: 'Item 5' },
            { id: 6, name: 'Item 6' },
            { id: 7, name: 'Item 7' },
            { id: 8, name: 'Item 8' },
            { id: 9, name: 'Item 9' },
            { id: 10, name: 'Item 10' }
          ];
          
          return (
            <div>
              {items.map(item => (
                <div key={item.id}>{item.name}</div>
              ))}
            </div>
          );
        };
        
        export default LongComponent;
      TSX
    )
    
    # Use ellipsis to replace the items array
    args = {
      'file_path' => 'src/components/LongComponent.tsx',
      'search' => "  const items = [\n    { id: 1, name: 'Item 1' },\n...\n    { id: 10, name: 'Item 10' }\n  ];",
      'first_replaced_line' => 4,
      'last_replaced_line' => 15,
      'replace' => "  const items = [\n    { id: 1, name: 'Updated Item' }\n  ];"
    }
    
    result = @builder.send(:replace_file_content, args)
    
    assert result[:success]
    long_file.reload
    assert_includes long_file.content, 'Updated Item'
    assert_not_includes long_file.content, 'Item 2'
    assert_not_includes long_file.content, 'Item 10'
  end

  test "replace_file_content validates line range properly" do
    args = {
      'file_path' => 'src/components/Button.tsx',
      'search' => 'some content',
      'first_replaced_line' => 100,  # Beyond file length
      'last_replaced_line' => 105,
      'replace' => 'new content'
    }
    
    result = @builder.send(:replace_file_content, args)
    
    assert_not result[:success]
    assert_includes result[:error], 'Invalid line range'
  end

  test "replace_file_content handles missing file gracefully" do
    args = {
      'file_path' => 'src/components/NonExistent.tsx',
      'search' => 'content',
      'first_replaced_line' => 1,
      'last_replaced_line' => 2,
      'replace' => 'new content'
    }
    
    result = @builder.send(:replace_file_content, args)
    
    assert_not result[:success]
    assert_includes result[:error], 'File not found'
  end

  test "replace_file_content preserves line endings properly" do
    args = {
      'file_path' => 'src/components/Button.tsx',
      'search' => '  return (',
      'first_replaced_line' => 4,
      'last_replaced_line' => 4,
      'replace' => '  console.log("test");\n  return ('
    }
    
    result = @builder.send(:replace_file_content, args)
    
    assert result[:success]
    @test_file.reload
    
    # Check that line endings are preserved
    lines = @test_file.content.lines
    assert_equal 12, lines.count  # Should have one more line now
    assert @test_file.content.end_with?("\n")
  end

  test "replace_file_content does not duplicate content" do
    original_content = @test_file.content
    original_lines = original_content.lines.count
    
    # Perform a replacement
    args = {
      'file_path' => 'src/components/Button.tsx',
      'search' => "const Button = () => {",
      'first_replaced_line' => 3,
      'last_replaced_line' => 3,
      'replace' => "const Button: React.FC = () => {"
    }
    
    result = @builder.send(:replace_file_content, args)
    assert result[:success]
    
    @test_file.reload
    new_content = @test_file.content
    new_lines = new_content.lines.count
    
    # Lines count should remain the same
    assert_equal original_lines, new_lines
    
    # Check no duplication occurred
    assert_equal 1, new_content.scan(/const Button/).count
    assert_not_includes new_content, "const Button = () => {\nconst Button"
  end

  test "replace_file_content handles multiple replacements without corruption" do
    # First replacement
    args1 = {
      'file_path' => 'src/components/Button.tsx',
      'first_replaced_line' => 5,
      'last_replaced_line' => 5,
      'replace' => '    <button className="primary">'
    }
    
    result1 = @builder.send(:replace_file_content, args1)
    assert result1[:success]
    
    @test_file.reload
    
    # Second replacement on the same file
    args2 = {
      'file_path' => 'src/components/Button.tsx',
      'first_replaced_line' => 6,
      'last_replaced_line' => 6,
      'replace' => '      Click me now'
    }
    
    result2 = @builder.send(:replace_file_content, args2)
    assert result2[:success]
    
    @test_file.reload
    final_content = @test_file.content
    
    # Verify both replacements worked and no corruption
    assert_includes final_content, 'className="primary"'
    assert_includes final_content, 'Click me now'
    assert_equal 11, final_content.lines.count
  end

  test "replace_file_content handles empty replacement correctly" do
    args = {
      'file_path' => 'src/components/Button.tsx',
      'first_replaced_line' => 5,
      'last_replaced_line' => 7,
      'replace' => ''  # Empty replacement (deletion)
    }
    
    original_lines = @test_file.content.lines.count
    result = @builder.send(:replace_file_content, args)
    
    assert result[:success]
    @test_file.reload
    
    # Should have fewer lines after deletion
    new_lines = @test_file.content.lines.count
    assert_equal original_lines - 3, new_lines
  end

  test "integration with LineReplaceService when available" do
    # Mock LineReplaceService if it's available
    if defined?(Ai::LineReplaceService)
      mock_result = { success: true }
      Ai::LineReplaceService.stub(:replace_lines, mock_result) do
        args = {
          'file_path' => 'src/components/Button.tsx',
          'search' => 'old content',
          'first_replaced_line' => 1,
          'last_replaced_line' => 2,
          'replace' => 'new content'
        }
        
        result = @builder.send(:replace_file_content, args)
        assert_equal mock_result, result
      end
    else
      skip "LineReplaceService not available"
    end
  end

  test "replace_file_content logs warnings for pattern mismatches" do
    args = {
      'file_path' => 'src/components/Button.tsx',
      'search' => 'this does not exist in the file',
      'first_replaced_line' => 5,
      'last_replaced_line' => 7,
      'replace' => 'new content'
    }
    
    # Capture logs
    Rails.logger.stub(:warn, ->(msg) { assert_includes msg, "Pattern mismatch" }) do
      result = @builder.send(:replace_file_content, args)
      # Should still succeed for backward compatibility
      assert result[:success]
    end
  end
end