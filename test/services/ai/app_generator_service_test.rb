require "test_helper"

module AI
  class AppGeneratorServiceTest < ActiveSupport::TestCase
    setup do
      @team = teams(:one)
      @app = apps(:one)
      @generation = app_generations(:one)
      @service = AI::AppGeneratorService.new(@app, @generation)
    end

    test "should initialize with app and generation" do
      assert_equal @app, @service.app
      assert_equal @generation, @service.generation
    end

    test "should enhance prompt with context" do
      prompt = "Create a todo app"
      enhanced = @service.send(:enhance_prompt, prompt)
      
      assert enhanced.length > prompt.length
      assert enhanced.include?("todo app")
    end

    test "should parse valid JSON AI response" do
      json_response = {
        app: {
          name: "Test App",
          description: "A test application"
        },
        files: [
          {
            path: "index.html",
            content: "<html></html>",
            type: "html"
          }
        ]
      }.to_json

      result = @service.send(:parse_ai_response, json_response)
      
      assert_not_nil result
      assert_equal "Test App", result[:app]["name"]
      assert_equal 1, result[:files].length
    end

    test "should parse JSON from markdown code blocks" do
      markdown_response = <<~MARKDOWN
        Here's the response:
        
        ```json
        {
          "app": {"name": "Test App"},
          "files": []
        }
        ```
      MARKDOWN

      result = @service.send(:parse_ai_response, markdown_response)
      
      assert_not_nil result
      assert_equal "Test App", result[:app]["name"]
    end

    test "should validate security scan passes for safe code" do
      files = [
        { "path" => "index.html", "content" => "<h1>Hello</h1>" },
        { "path" => "app.js", "content" => "console.log('safe');" }
      ]

      assert @service.send(:security_scan_passed?, files)
    end

    test "should create app files from parsed data" do
      files_data = [
        {
          "path" => "test.html",
          "content" => "<h1>Test</h1>",
          "type" => "html"
        }
      ]

      assert_difference 'AppFile.count', 1 do
        @service.send(:create_app_files, files_data)
      end

      file = AppFile.last
      assert_equal "test.html", file.path
      assert_equal "<h1>Test</h1>", file.content
      assert_equal "html", file.file_type
    end

    test "should update app metadata" do
      metadata = {
        "name" => "Updated App",
        "description" => "An updated description",
        "features" => ["feature1", "feature2"]
      }

      @service.send(:update_app_metadata, metadata)
      @app.reload

      assert_equal "Updated App", @app.name
      assert_equal "An updated description", @app.description
    end

    test "should handle generation failure gracefully" do
      # Mock a failed AI response
      @service.stub(:generate_with_ai, { success: false, error: "API Error" }) do
        result = @service.generate!
        
        assert_not result[:success]
        assert_equal "AI generation failed: API Error", result[:error]
        assert_equal "failed", @generation.reload.status
      end
    end
  end
end