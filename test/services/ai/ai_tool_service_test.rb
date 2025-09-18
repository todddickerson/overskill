require "test_helper"

class Ai::AiToolServiceTest < ActiveSupport::TestCase
  setup do
    @app = create(:app)
    @user = create(:user)
    @service = Ai::AiToolService.new(@app, user: @user)
  end

  # ========================
  # File Management Tests
  # ========================

  test "write_file creates new file successfully" do
    result = @service.write_file("test.js", "console.log('test');")

    assert result[:success]
    assert_equal "File test.js written successfully", result[:content]

    file = @app.app_files.find_by(path: "test.js")
    assert_not_nil file
    assert_equal "console.log('test');", file.content
  end

  test "write_file updates existing file" do
    create(:app_file, app: @app, path: "existing.js", content: "old content")

    result = @service.write_file("existing.js", "new content")

    assert result[:success]
    file = @app.app_files.find_by(path: "existing.js")
    assert_equal "new content", file.content
  end

  test "write_file returns error for blank path" do
    result = @service.write_file("", "content")

    assert_not result[:success]
    assert_equal "File path cannot be blank", result[:error]
  end

  test "write_file returns error for blank content" do
    result = @service.write_file("test.js", "")

    assert_not result[:success]
    assert_equal "Content cannot be blank", result[:error]
  end

  test "read_file retrieves existing file content" do
    create(:app_file, app: @app, path: "test.js", content: "const x = 1;")

    result = @service.read_file("test.js")

    assert result[:success]
    assert_equal "const x = 1;", result[:content]
  end

  test "read_file returns error for non-existent file" do
    result = @service.read_file("nonexistent.js")

    assert_not result[:success]
    assert_equal "File not found: nonexistent.js", result[:error]
  end

  test "read_file applies line filter when provided" do
    content = (1..10).map { |i| "Line #{i}" }.join("\n")
    create(:app_file, app: @app, path: "test.txt", content: content)

    result = @service.read_file("test.txt", "2-4")

    assert result[:success]
    assert_includes result[:content], "Line 2"
    assert_includes result[:content], "Line 3"
    assert_includes result[:content], "Line 4"
    assert_not_includes result[:content], "Line 1"
    assert_not_includes result[:content], "Line 5"
  end

  test "delete_file removes existing file" do
    create(:app_file, app: @app, path: "test.js", content: "content")

    result = @service.delete_file("test.js")

    assert result[:success]
    assert_equal "File test.js deleted successfully", result[:content]
    assert_nil @app.app_files.find_by(path: "test.js")
  end

  test "delete_file returns error for non-existent file" do
    result = @service.delete_file("nonexistent.js")

    assert_not result[:success]
    assert_equal "File not found: nonexistent.js", result[:error]
  end

  test "rename_file changes file path" do
    create(:app_file, app: @app, path: "old.js", content: "content")

    result = @service.rename_file("old.js", "new.js")

    assert result[:success]
    assert_equal "File renamed from old.js to new.js", result[:content]
    assert_nil @app.app_files.find_by(path: "old.js")
    assert_not_nil @app.app_files.find_by(path: "new.js")
  end

  # ========================
  # On-Demand File Creation Tests
  # ========================

  test "read_file creates file on-demand from GitHub template when not found" do
    # Mock GitHub authentication
    mock_authenticator = mock("GithubAppAuthenticator")
    mock_authenticator.expects(:get_installation_token).returns("test-token")
    Deployment::GithubAppAuthenticator.stubs(:new).returns(mock_authenticator)

    # Mock GitHub API response
    github_response = mock("HTTParty::Response")
    github_response.stubs(:code).returns(200)
    github_response.stubs(:[]).with("content").returns(Base64.encode64("export default function App() { return <div>Hello</div>; }"))
    HTTParty.stubs(:get).returns(github_response)

    result = @service.read_file("src/App.tsx")

    assert result[:success]
    assert_includes result[:content], "export default function App"

    # Verify file was created
    file = @app.app_files.find_by(path: "src/App.tsx")
    assert_not_nil file
    assert_equal "typescript", file.file_type
  end

  test "replace_file_content creates file on-demand when not found" do
    # Mock GitHub authentication
    mock_authenticator = mock("GithubAppAuthenticator")
    mock_authenticator.expects(:get_installation_token).returns("test-token")
    Deployment::GithubAppAuthenticator.stubs(:new).returns(mock_authenticator)

    # Mock GitHub API response
    github_response = mock("HTTParty::Response")
    github_response.stubs(:code).returns(200)
    github_response.stubs(:[]).with("content").returns(Base64.encode64("module.exports = {\n  content: []\n}"))
    HTTParty.stubs(:get).returns(github_response)

    result = @service.replace_file_content(
      "tailwind.config.js",
      "content: []",
      "1",
      "2",
      "content: ['./src/**/*.{js,jsx,ts,tsx}']"
    )

    assert result[:success]

    # Verify file was created
    file = @app.app_files.find_by(path: "tailwind.config.js")
    assert_not_nil file
    assert_equal "javascript", file.file_type
    assert_includes file.content, "./src/**/*.{js,jsx,ts,tsx}"
  end

  test "on-demand creation handles GitHub API errors gracefully" do
    # Mock GitHub authentication
    mock_authenticator = mock("GithubAppAuthenticator")
    mock_authenticator.expects(:get_installation_token).returns("test-token")
    Deployment::GithubAppAuthenticator.stubs(:new).returns(mock_authenticator)

    # Mock GitHub API 404 response
    github_response = mock("HTTParty::Response")
    github_response.stubs(:code).returns(404)
    HTTParty.stubs(:get).returns(github_response)

    result = @service.read_file("nonexistent.txt")

    assert_not result[:success]
    assert_equal "File not found: nonexistent.txt", result[:error]
  end

  test "on-demand creation handles authentication failures" do
    # Mock GitHub authentication failure
    mock_authenticator = mock("GithubAppAuthenticator")
    mock_authenticator.expects(:get_installation_token).returns(nil)
    Deployment::GithubAppAuthenticator.stubs(:new).returns(mock_authenticator)

    result = @service.read_file("src/App.tsx")

    assert_not result[:success]
    assert_equal "File not found: src/App.tsx", result[:error]
  end

  test "write_file handles R2 storage correctly with proper associations" do
    # Test that AppFile is saved before content to establish app.id
    large_content = "x" * 10000 # Content that triggers R2 storage

    result = @service.write_file("large.txt", large_content)

    assert result[:success]

    file = @app.app_files.find_by(path: "large.txt")
    assert_not_nil file
    assert_not_nil file.app_id
    assert_equal @app.id, file.app_id
    assert_equal large_content, file.content
  end

  test "file type detection works correctly for various extensions" do
    # Mock GitHub authentication
    mock_authenticator = mock("GithubAppAuthenticator")
    mock_authenticator.expects(:get_installation_token).returns("test-token")
    Deployment::GithubAppAuthenticator.stubs(:new).returns(mock_authenticator)

    test_cases = {
      "app.tsx" => "typescript",
      "script.js" => "javascript",
      "styles.css" => "css",
      "config.json" => "json",
      "README.md" => "markdown",
      "config.yaml" => "yaml",
      "logo.svg" => "svg"
    }

    test_cases.each do |filename, expected_type|
      # Mock GitHub API response
      github_response = mock("HTTParty::Response")
      github_response.stubs(:code).returns(200)
      github_response.stubs(:[]).with("content").returns(Base64.encode64("test content"))
      HTTParty.stubs(:get).returns(github_response)

      result = @service.read_file(filename)

      assert result[:success], "Failed to read #{filename}"

      file = @app.app_files.find_by(path: filename)
      assert_not_nil file, "File #{filename} was not created"
      assert_equal expected_type, file.file_type, "Wrong file type for #{filename}"
    end
  end

  # ========================
  # Package Management Tests
  # ========================

  test "add_dependency adds package to package.json" do
    package_json = create(:app_file, app: @app, path: "package.json",
      content: '{"dependencies": {}}')

    result = @service.add_dependency("lodash@4.17.21")

    assert result[:success]
    assert_equal "Added dependency: lodash@4.17.21", result[:content]

    json = JSON.parse(package_json.reload.content)
    assert_equal "4.17.21", json["dependencies"]["lodash"]
  end

  test "add_dependency creates package.json if not exists" do
    result = @service.add_dependency("lodash")

    assert result[:success]

    package_json = @app.app_files.find_by(path: "package.json")
    assert_not_nil package_json

    json = JSON.parse(package_json.content)
    assert_equal "latest", json["dependencies"]["lodash"]
  end

  test "remove_dependency removes package from package.json" do
    package_json = create(:app_file, app: @app, path: "package.json",
      content: '{"dependencies": {"lodash": "4.17.21"}}')

    result = @service.remove_dependency("lodash")

    assert result[:success]
    assert_equal "Removed dependency: lodash", result[:content]

    json = JSON.parse(package_json.reload.content)
    assert_empty json["dependencies"]
  end

  test "remove_dependency returns error if package not found" do
    create(:app_file, app: @app, path: "package.json",
      content: '{"dependencies": {}}')

    result = @service.remove_dependency("nonexistent")

    assert_not result[:success]
    assert_equal "Package nonexistent not found in dependencies", result[:error]
  end

  # ========================
  # Web Research Tests
  # ========================

  test "web_search returns error without API key" do
    with_env_var("SERPAPI_API_KEY", nil) do
      result = @service.web_search("query" => "test search")

      assert_not result[:success]
      assert_equal "SerpAPI key not configured", result[:error]
    end
  end

  test "web_search formats results correctly" do
    skip "Requires SerpAPI key for integration test"
  end

  test "fetch_webpage delegates to WebContentExtractionService" do
    mock_service = mock("WebContentExtractionService")
    mock_service.expects(:extract_for_llm).with("https://example.com", use_cache: true)
      .returns(
        url: "https://example.com",
        title: "Example",
        content: "Test content",
        word_count: 2,
        char_count: 12,
        extracted_at: Time.current.iso8601
      )

    Ai::AiToolService.any_instance.stubs(:initialize_web_content_service).returns(mock_service)
    service = Ai::AiToolService.new(@app)

    result = service.fetch_webpage("https://example.com", true)

    assert result[:success]
    assert_includes result[:content], "Example"
    assert_includes result[:content], "Test content"
  end

  test "perplexity_research handles quick mode" do
    mock_service = mock("PerplexityContentService")
    mock_service.expects(:extract_content_for_llm)
      .with("test query", hash_including(model: PerplexityContentService::MODELS[:sonar]))
      .returns(
        success: true,
        content: "Quick research result",
        word_count: 3,
        has_citations: true
      )

    Ai::AiToolService.any_instance.stubs(:initialize_perplexity_service).returns(mock_service)
    service = Ai::AiToolService.new(@app)

    result = service.perplexity_research("query" => "test query", "mode" => "quick")

    assert result[:success]
    assert_includes result[:content], "Quick research result"
  end

  test "perplexity_research handles fact_check mode" do
    mock_service = mock("PerplexityContentService")
    mock_service.expects(:fact_check).with("test statement")
      .returns(
        success: true,
        content: "Fact check result",
        has_citations: true
      )

    Ai::AiToolService.any_instance.stubs(:initialize_perplexity_service).returns(mock_service)
    service = Ai::AiToolService.new(@app)

    result = service.perplexity_research("query" => "test statement", "mode" => "fact_check")

    assert result[:success]
    assert_includes result[:content], "Fact check result"
  end

  test "perplexity_research handles deep research mode" do
    mock_service = mock("PerplexityContentService")
    mock_service.expects(:deep_research).with("complex topic")
      .returns(
        success: true,
        research_report: "Comprehensive research report",
        word_count: 3
      )

    Ai::AiToolService.any_instance.stubs(:initialize_perplexity_service).returns(mock_service)
    service = Ai::AiToolService.new(@app)

    result = service.perplexity_research("query" => "complex topic", "mode" => "deep")

    assert result[:success]
    assert_includes result[:content], "Comprehensive research report"
  end

  # ========================
  # Image Generation Tests
  # ========================

  test "generate_image validates required parameters" do
    result = @service.generate_image({})

    assert_not result[:success]
    assert_equal "Prompt is required", result[:error]

    result = @service.generate_image("prompt" => "test")

    assert_not result[:success]
    assert_equal "Target path is required", result[:error]
  end

  test "edit_image validates required parameters" do
    result = @service.edit_image({})

    assert_not result[:success]
    assert_equal "Image paths are required", result[:error]

    result = @service.edit_image("image_paths" => ["test.jpg"])

    assert_not result[:success]
    assert_equal "Prompt is required", result[:error]
  end

  # ========================
  # Utility Tests
  # ========================

  test "download_to_repo validates parameters" do
    result = @service.download_to_repo("", "target.txt")

    assert_not result[:success]
    assert_equal "Source URL is required", result[:error]

    result = @service.download_to_repo("https://example.com", "")

    assert_not result[:success]
    assert_equal "Target path is required", result[:error]
  end

  private

  def with_env_var(key, value)
    old_value = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old_value
  end
end
