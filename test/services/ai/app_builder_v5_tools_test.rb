require "test_helper"

class Ai::AppBuilderV5ToolsTest < ActiveSupport::TestCase
  setup do
    # Create test user
    @user = User.create!(
      email: "test_v5_#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      first_name: "Test",
      last_name: "User",
      time_zone: "UTC"
    )

    # Create test team
    @team = @user.teams.create!(
      name: "Test Team #{SecureRandom.hex(4)}"
    )

    # Create test membership
    @membership = @team.memberships.find_by(user: @user) ||
      @team.memberships.create!(user: @user, roles: ["admin"])

    # Create test app
    @app = @team.apps.create!(
      name: "Test App",
      status: "generating",
      prompt: "Test prompt",
      creator: @membership,
      app_type: "tool"
    )

    # Create test chat message
    @chat_message = AppChatMessage.create!(
      app: @app,
      user: @user,
      role: "user",
      content: "Test message"
    )

    # Initialize builder
    @builder = Ai::AppBuilderV5.new(@chat_message)

    # Stub get_or_create_template_version to return nil in tests
    def @builder.get_or_create_template_version
      nil
    end
  end

  # ============================================
  # os-write tool tests
  # ============================================
  test "os-write creates new file" do
    file_path = "src/App.tsx"
    content = "import React from 'react';\nexport default function App() { return <div>Hello</div>; }"

    result = @builder.send(:write_file, file_path, content)

    assert result[:success]
    assert_equal file_path, result[:path]
    assert result[:file_id].present?

    # Verify file was created
    file = @app.app_files.find_by(path: file_path)
    assert file.present?
    assert_equal content, file.content
    assert_equal "typescript", file.file_type
  end

  test "os-write updates existing file" do
    # Create initial file
    initial_content = "const x = 1;"
    file = @app.app_files.create!(
      path: "src/test.js",
      content: initial_content,
      file_type: "javascript",
      team: @team
    )

    # Update file
    new_content = "const x = 2;"
    result = @builder.send(:write_file, "src/test.js", new_content)

    assert result[:success]
    file.reload
    assert_equal new_content, file.content
  end

  test "os-write detects correct language from extension" do
    test_cases = {
      "app.tsx" => "typescript",
      "app.ts" => "typescript",
      "app.jsx" => "javascript",
      "app.js" => "javascript",
      "styles.css" => "css",
      "package.json" => "json",
      "README.md" => "text"
    }

    test_cases.each do |filename, expected_language|
      @builder.send(:write_file, filename, "test content")
      file = @app.app_files.find_by(path: filename)
      assert_equal expected_language, file.file_type, "Wrong file type for #{filename}"
    end
  end

  # ============================================
  # os-view/os-read tool tests
  # ============================================
  test "os-view reads existing file from app" do
    # Create test file
    file = @app.app_files.create!(
      path: "src/existing.ts",
      content: "console.log('test');",
      file_type: "typescript",
      team: @team
    )

    result = @builder.send(:read_file, "src/existing.ts")

    assert result[:success]
    assert_equal file.content, result[:content]
    assert_equal "generated", result[:source]
  end

  test "os-view reads file from template directory" do
    skip "Template directory test - requires template files to be present"
  end

  test "os-view returns error for non-existent file" do
    result = @builder.send(:read_file, "non/existent/file.txt")

    assert result[:error].present?
    assert_match(/File not found/, result[:error])
  end

  # ============================================
  # os-line-replace tool tests
  # ============================================
  test "os-line-replace replaces content in existing file" do
    # Create file with multiple lines
    original_content = "line1\nline2\nline3\nline4\nline5"
    file = @app.app_files.create!(
      path: "src/test.txt",
      content: original_content,
      file_type: "text",
      team: @team
    )

    args = {
      "file_path" => "src/test.txt",
      "first_replaced_line" => 2,
      "last_replaced_line" => 4,
      "replace" => "new line 2\nnew line 3\nnew line 4"
    }

    result = @builder.send(:replace_file_content, args)

    assert result[:success]
    file.reload
    expected = "line1\nnew line 2\nnew line 3\nnew line 4\nline5"
    assert_equal expected, file.content
  end

  test "os-line-replace returns error for non-existent file" do
    args = {
      "file_path" => "non/existent.txt",
      "first_replaced_line" => 1,
      "last_replaced_line" => 1,
      "replace" => "new content"
    }

    result = @builder.send(:replace_file_content, args)

    assert result[:error].present?
    assert_match(/File not found/, result[:error])
  end

  test "os-line-replace handles single line replacement" do
    file = @app.app_files.create!(
      path: "src/single.txt",
      content: "line1\nline2\nline3",
      file_type: "text",
      team: @team
    )

    args = {
      "file_path" => "src/single.txt",
      "first_replaced_line" => 2,
      "last_replaced_line" => 2,
      "replace" => "replaced line 2"
    }

    result = @builder.send(:replace_file_content, args)

    assert result[:success]
    file.reload
    assert_equal "line1\nreplaced line 2\nline3", file.content
  end

  # ============================================
  # os-delete tool tests
  # ============================================
  test "os-delete removes existing file" do
    @app.app_files.create!(
      path: "src/to_delete.txt",
      content: "delete me",
      file_type: "text",
      team: @team
    )

    result = @builder.send(:delete_file, "src/to_delete.txt")

    assert result[:success]
    assert_equal "src/to_delete.txt", result[:path]
    assert_nil @app.app_files.find_by(path: "src/to_delete.txt")
  end

  test "os-delete returns error for non-existent file" do
    result = @builder.send(:delete_file, "non/existent.txt")

    assert result[:error].present?
    assert_match(/File not found/, result[:error])
  end

  # ============================================
  # os-add-dependency tool tests
  # ============================================
  test "os-add-dependency adds new dependency to package.json" do
    # Create initial package.json
    package_json = {
      "name" => "test-app",
      "version" => "1.0.0",
      "dependencies" => {
        "react" => "^18.0.0"
      }
    }.to_json

    # Ensure clean package.json for this test
    existing = @app.app_files.find_by(path: "package.json")
    existing&.destroy

    @app.app_files.create!(
      path: "package.json",
      content: package_json,
      file_type: "json",
      team: @team
    )

    result = @builder.send(:add_dependency, "lodash@^4.17.21")

    assert result[:success]
    assert_equal "lodash", result[:package]
    assert_equal "^4.17.21", result[:version]

    # Verify package.json was updated
    file = @app.app_files.find_by(path: "package.json")
    package_data = JSON.parse(file.content)
    assert_equal "^4.17.21", package_data["dependencies"]["lodash"]
  end

  test "os-add-dependency creates package.json if it doesn't exist" do
    result = @builder.send(:add_dependency, "express@latest")

    assert result[:success]

    file = @app.app_files.find_by(path: "package.json")
    assert file.present?

    package_data = JSON.parse(file.content)
    assert package_data["dependencies"]["express"].present?
  end

  # ============================================
  # os-remove-dependency tool tests
  # ============================================
  test "os-remove-dependency removes existing dependency" do
    package_json = {
      "name" => "test-app",
      "dependencies" => {
        "react" => "^18.0.0",
        "lodash" => "^4.17.21"
      }
    }.to_json

    # Ensure clean package.json for this test
    existing = @app.app_files.find_by(path: "package.json")
    existing&.destroy

    @app.app_files.create!(
      path: "package.json",
      content: package_json,
      file_type: "json",
      team: @team
    )

    result = @builder.send(:remove_dependency, "lodash")

    assert result[:success]

    file = @app.app_files.find_by(path: "package.json")
    package_data = JSON.parse(file.content)
    assert_nil package_data["dependencies"]["lodash"]
    assert_equal "^18.0.0", package_data["dependencies"]["react"]
  end

  # ============================================
  # os-rename tool tests
  # ============================================
  test "os-rename renames existing file" do
    @app.app_files.create!(
      path: "src/old_name.txt",
      content: "test content",
      file_type: "text",
      team: @team
    )

    result = @builder.send(:rename_file, "src/old_name.txt", "src/new_name.txt")

    assert result[:success]
    assert_nil @app.app_files.find_by(path: "src/old_name.txt")

    renamed_file = @app.app_files.find_by(path: "src/new_name.txt")
    assert renamed_file.present?
    assert_equal "test content", renamed_file.content
  end

  # ============================================
  # os-search-files tool tests
  # ============================================
  test "os-search-files finds matching content" do
    # Clear any existing files to ensure clean test
    @app.app_files.destroy_all

    # Create test files
    @app.app_files.create!(
      path: "src/component1.tsx",
      content: "const Component1 = () => { useState(); return <div>Test</div>; }",
      file_type: "typescript",
      team: @team
    )

    @app.app_files.create!(
      path: "src/component2.tsx",
      content: "const Component2 = () => { return <div>No hooks</div>; }",
      file_type: "typescript",
      team: @team
    )

    @app.app_files.create!(
      path: "test/test.tsx",
      content: "describe('test', () => { useState(); });",
      file_type: "typescript",
      team: @team
    )

    args = {
      "query" => "useState",
      "include_pattern" => "src/",
      "case_sensitive" => false
    }

    result = @builder.send(:search_files, args)

    assert result[:success]
    assert_equal 1, result[:matches].count
    assert_equal "src/component1.tsx", result[:matches].first[:path]
  end

  # ============================================
  # Tool execution through process_tool_calls
  # ============================================
  test "process_tool_calls executes multiple tools" do
    tool_calls = [
      {
        "function" => {
          "name" => "os-write",
          "arguments" => {
            "file_path" => "test1.txt",
            "content" => "content1"
          }.to_json
        }
      },
      {
        "function" => {
          "name" => "os-write",
          "arguments" => {
            "file_path" => "test2.txt",
            "content" => "content2"
          }.to_json
        }
      }
    ]

    results = @builder.send(:process_tool_calls, tool_calls)

    assert_equal 2, results.count
    assert results.all? { |r| r[:success] }

    assert @app.app_files.find_by(path: "test1.txt").present?
    assert @app.app_files.find_by(path: "test2.txt").present?
  end

  test "process_tool_calls handles unknown tools gracefully" do
    tool_calls = [
      {
        "function" => {
          "name" => "unknown-tool",
          "arguments" => {}.to_json
        }
      }
    ]

    results = @builder.send(:process_tool_calls, tool_calls)

    assert_equal 1, results.count
    assert results.first[:error].present?
    assert_match(/Unknown tool/, results.first[:error])
  end

  # ============================================
  # os-download-to-repo tool tests
  # ============================================
  test "os-download-to-repo creates placeholder file" do
    result = @builder.send(:download_to_repo, "https://example.com/test.png", "assets/test.png")

    assert result[:success]
    assert_equal "assets/test.png", result[:path]

    file = @app.app_files.find_by(path: "assets/test.png")
    assert file.present?
    assert_match(/Downloaded from: https:\/\/example.com\/test.png/, file.content)
  end

  # ============================================
  # os-fetch-website tool tests
  # ============================================
  test "os-fetch-website returns website content" do
    result = @builder.send(:fetch_website, "https://example.com", "markdown")

    assert result[:success]
    assert_equal "https://example.com", result[:url]
    assert result[:content].include?("Website Content")
    assert_equal "markdown", result[:formats]
  end

  # ============================================
  # os-read-console-logs tool tests
  # ============================================
  test "os-read-console-logs returns filtered logs" do
    result = @builder.send(:read_console_logs, "error")

    assert result[:success]
    assert_equal "error", result[:search_query]
    assert result[:logs].any? { |log| log.downcase.include?("error") }
    assert_equal result[:logs].count, result[:total_found]
  end

  test "os-read-console-logs returns all logs when no search query" do
    result = @builder.send(:read_console_logs, nil)

    assert result[:success]
    assert result[:logs].count >= 3 # Mock data has at least 3 logs
  end

  # ============================================
  # os-read-network-requests tool tests
  # ============================================
  test "os-read-network-requests returns filtered requests" do
    result = @builder.send(:read_network_requests, "500")

    assert result[:success]
    assert_equal "500", result[:search_query]
    assert result[:requests].any? { |req| req.include?("500") }
  end

  # ============================================
  # generate_image tool tests
  # ============================================
  test "generate_image creates placeholder file with valid dimensions" do
    skip "ImageGenerationService requires external dependencies"
    args = {
      "prompt" => "A beautiful sunset",
      "target_path" => "src/assets/sunset.jpg",
      "width" => 512,
      "height" => 512,
      "model" => "flux.schnell"
    }

    # Since we're in test mode, stub the ImageGenerationService to avoid external calls
    # Create a simple mock that returns the expected result

    # Stub the service instance method to return our mock result
    image_service_stub = Object.new
    def image_service_stub.generate_and_save_image(options)
      {
        success: true,
        dimensions: "#{options[:width]}x#{options[:height]}",
        provider: "test"
      }
    end

    # Replace the service instantiation with our stub
    Ai::ImageGenerationService.stub :new, image_service_stub do
      result = @builder.send(:generate_image, args)

      assert result[:success]
      assert_equal "src/assets/sunset.jpg", result[:path]
      assert_equal "A beautiful sunset", result[:prompt]
      assert_equal "512x512", result[:dimensions]
    end
  end

  test "generate_image validates dimensions" do
    args = {
      "prompt" => "Test image",
      "target_path" => "test.jpg",
      "width" => 400, # Invalid - less than 512
      "height" => 400
    }

    result = @builder.send(:generate_image, args)

    assert result[:error].present?
    assert_match(/dimensions must be between 512 and 1920/, result[:error])
  end

  test "generate_image validates dimension multiples" do
    args = {
      "prompt" => "Test image",
      "target_path" => "test.jpg",
      "width" => 513, # Invalid - not multiple of 32
      "height" => 512
    }

    result = @builder.send(:generate_image, args)

    assert result[:error].present?
    assert_match(/dimensions must be multiples of 32/, result[:error])
  end

  # ============================================
  # edit_image tool tests
  # ============================================
  test "edit_image creates placeholder with existing source images" do
    # Create source image
    @app.app_files.create!(
      path: "src/assets/original.jpg",
      content: "original image content",
      file_type: "image",
      team: @team
    )

    args = {
      "image_paths" => ["src/assets/original.jpg"],
      "prompt" => "make it darker",
      "target_path" => "src/assets/edited.jpg",
      "strength" => 0.7
    }

    result = @builder.send(:edit_image, args)

    assert result[:success]
    assert_equal "src/assets/edited.jpg", result[:path]
    assert_equal ["src/assets/original.jpg"], result[:source_images]
    assert_equal 0.7, result[:strength]
  end

  test "edit_image validates source images exist" do
    args = {
      "image_paths" => ["non/existent.jpg"],
      "prompt" => "edit this",
      "target_path" => "edited.jpg"
    }

    result = @builder.send(:edit_image, args)

    assert result[:error].present?
    assert_match(/Source images not found/, result[:error])
  end

  # ============================================
  # web_search tool tests
  # ============================================
  test "web_search returns search results" do
    args = {
      "query" => "react hooks",
      "numResults" => 3,
      "category" => "documentation"
    }

    result = @builder.send(:web_search, args)

    assert result[:success]
    assert_equal "react hooks", result[:query]
    assert_equal 3, result[:results].count
    assert result[:results].first[:title].include?("react hooks")
  end

  # ============================================
  # read_project_analytics tool tests
  # ============================================
  test "read_project_analytics returns analytics data" do
    args = {
      "startdate" => "2025-01-01",
      "enddate" => "2025-01-31",
      "granularity" => "daily"
    }

    result = @builder.send(:read_project_analytics, args)

    assert result[:success]
    assert_equal @app.id, result[:app_id]
    assert result[:data][:metrics][:page_views].present?
    assert result[:data][:traffic_sources][:organic].present?
  end
end
