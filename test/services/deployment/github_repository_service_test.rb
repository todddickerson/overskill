require "test_helper"

class Deployment::GithubRepositoryServiceTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @membership = create(:membership, team: @team)
    @app = create(:app, team: @team, creator: @membership)
    # obfuscated_id is automatically set by BulletTrain

    # Mock environment variables
    ENV["GITHUB_TOKEN"] = "test_token"
    ENV["GITHUB_ORG"] = "Overskill-apps"
    ENV["GITHUB_TEMPLATE_REPO"] = "Overskill-apps/vite-app-template"

    @service = Deployment::GithubRepositoryService.new(@app)
  end

  teardown do
    ENV.delete("GITHUB_TOKEN")
    ENV.delete("GITHUB_ORG")
    ENV.delete("GITHUB_TEMPLATE_REPO")
  end

  test "should initialize with required environment variables" do
    assert_not_nil @service
  end

  test "should raise error when environment variables are missing" do
    ENV.delete("GITHUB_TOKEN")

    assert_raises(RuntimeError) do
      Deployment::GithubRepositoryService.new(@app)
    end
  end

  test "generate_unique_repo_name uses obfuscated_id for privacy" do
    # Use send to test private method
    repo_name = @service.send(:generate_unique_repo_name)

    assert_includes repo_name, @app.obfuscated_id
    assert_match(/^[\w-]+-[\w]+$/, repo_name)
  end

  test "create_app_repository_via_fork success scenario" do
    # Mock successful fork response
    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      "id" => 123456,
      "html_url" => "https://github.com/Overskill-apps/test-app-#{@app.obfuscated_id}",
      "name" => "test-app-#{@app.obfuscated_id}",
      "fork" => true
    })

    @service.class.stubs(:post).returns(mock_response)

    result = @service.create_app_repository_via_fork

    assert result[:success]
    assert_equal "test-app-#{@app.obfuscated_id}", result[:repo_name]
    assert result[:ready]
    assert_equal "2-3 seconds", result[:fork_time]

    # Verify app was updated
    @app.reload
    assert_equal "https://github.com/Overskill-apps/test-app-#{@app.obfuscated_id}", @app.repository_url
    assert_equal "test-app-#{@app.obfuscated_id}", @app.repository_name
    assert_equal 123456, @app.github_repo_id
    assert_equal "ready", @app.repository_status
  end

  test "create_app_repository_via_fork failure scenario" do
    # Mock failed fork response
    mock_response = mock
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:body).returns("Repository already exists")

    @service.class.stubs(:post).returns(mock_response)

    result = @service.create_app_repository_via_fork

    assert_not result[:success]
    assert_includes result[:error], "Fork failed"
  end

  test "update_file_in_repository creates new file" do
    # Mock GET response (file doesn't exist)
    get_response = mock
    get_response.stubs(:success?).returns(false)

    # Mock PUT response (file created)
    put_response = mock
    put_response.stubs(:success?).returns(true)
    put_response.stubs(:parsed_response).returns({
      "content" => {"sha" => "abc123"}
    })

    @service.class.stubs(:get).returns(get_response)
    @service.class.stubs(:put).returns(put_response)

    @app.update!(repository_name: "test-repo")

    result = @service.update_file_in_repository(
      path: "src/App.tsx",
      content: "export default function App() {}",
      message: "Create App component"
    )

    assert result[:success]
    assert_equal "abc123", result[:sha]
  end

  test "update_file_in_repository updates existing file" do
    # Mock GET response (file exists)
    get_response = mock
    get_response.stubs(:success?).returns(true)
    get_response.stubs(:parsed_response).returns({
      "sha" => "old_sha_123"
    })

    # Mock PUT response (file updated)
    put_response = mock
    put_response.stubs(:success?).returns(true)
    put_response.stubs(:parsed_response).returns({
      "content" => {"sha" => "new_sha_456"}
    })

    @service.class.stubs(:get).returns(get_response)
    @service.class.stubs(:put).returns(put_response)

    @app.update!(repository_name: "test-repo")

    result = @service.update_file_in_repository(
      path: "src/App.tsx",
      content: "export default function UpdatedApp() {}",
      message: "Update App component"
    )

    assert result[:success]
    assert_equal "new_sha_456", result[:sha]
  end

  test "push_file_structure handles multiple files" do
    @app.update!(repository_name: "test-repo")

    # Mock successful responses for each file
    @service.stubs(:update_file_in_repository).returns({success: true})

    file_structure = {
      "src/App.tsx" => "export default function App() {}",
      "src/index.tsx" => 'import App from "./App"',
      "src/styles.css" => "body { margin: 0; }"
    }

    result = @service.push_file_structure(file_structure)

    assert result[:success]
    assert_equal 3, result[:files_pushed]
  end

  test "push_file_structure handles partial failures" do
    @app.update!(repository_name: "test-repo")

    # Mock mixed responses - 2 success, 1 failure
    responses = [
      {success: true},
      {success: false, error: "Permission denied"},
      {success: true}
    ]

    @service.stubs(:update_file_in_repository).returns(*responses)

    file_structure = {
      "file1.js" => "content1",
      "file2.js" => "content2",
      "file3.js" => "content3"
    }

    result = @service.push_file_structure(file_structure)

    assert_not result[:success]
    assert result[:partial_success]
    assert_equal 1, result[:failed_files].size
  end

  test "get_repository_info retrieves repository details" do
    @app.update!(repository_name: "test-repo")

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      "name" => "test-repo",
      "html_url" => "https://github.com/Overskill-apps/test-repo",
      "fork" => true
    })

    @service.class.stubs(:get).returns(mock_response)

    result = @service.get_repository_info

    assert result[:success]
    assert_equal "test-repo", result[:repository]["name"]
  end

  test "list_repository_files returns file list" do
    @app.update!(repository_name: "test-repo")

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns([
      {"name" => "README.md"},
      {"name" => "package.json"},
      {"name" => "src"}
    ])

    @service.class.stubs(:get).returns(mock_response)

    result = @service.list_repository_files

    assert result[:success]
    assert_equal ["README.md", "package.json", "src"], result[:files]
  end

  test "methods fail gracefully when no repository exists" do
    @app.update!(repository_name: nil)

    result = @service.get_repository_info
    assert_not result[:success]
    assert_equal "No repository created", result[:error]

    result = @service.list_repository_files
    assert_not result[:success]
    assert_equal "No repository created", result[:error]
  end
end
