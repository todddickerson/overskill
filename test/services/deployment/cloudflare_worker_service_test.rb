require "test_helper"

class Deployment::CloudflareWorkerServiceTest < ActiveSupport::TestCase
  def setup
    @app = create(:app, :with_files)

    # Create some test files
    @app.app_files.destroy_all
    @app.app_files.create!(
      team: @app.team,
      path: "index.html",
      content: "<html><body><h1>Test App</h1></body></html>",
      file_type: "html",
      size_bytes: 45
    )
    @app.app_files.create!(
      team: @app.team,
      path: "script.js",
      content: "console.log('Hello World');",
      file_type: "javascript",
      size_bytes: 26
    )

    @service = Deployment::CloudflareWorkerService.new(@app)

    # Mock environment variables
    ENV["CLOUDFLARE_ACCOUNT_ID"] = "test-account-id"
    ENV["CLOUDFLARE_API_TOKEN"] = "test-api-token"
    ENV["CLOUDFLARE_ZONE_ID"] = "test-zone-id"
  end

  def teardown
    # Clean up environment variables
    ENV.delete("CLOUDFLARE_ACCOUNT_ID")
    ENV.delete("CLOUDFLARE_API_TOKEN")
    ENV.delete("CLOUDFLARE_ZONE_ID")
  end

  test "should generate unique subdomain from app name" do
    # Create new app instead of updating existing one
    app = create(:app, name: "My Test App")
    service = Deployment::CloudflareWorkerService.new(app)
    subdomain = service.send(:generate_subdomain)

    assert_includes subdomain, "my-test-app"
    assert_includes subdomain, app.id.to_s
  end

  test "should handle long app names by truncating" do
    # Create new app instead of updating existing one
    app = create(:app, name: "This Is A Very Long App Name That Should Be Truncated")
    service = Deployment::CloudflareWorkerService.new(app)
    subdomain = service.send(:generate_subdomain)

    assert subdomain.length <= 25
    assert_includes subdomain, app.id.to_s
  end

  test "should generate worker script with embedded files" do
    script = @service.send(:generate_worker_script)

    assert_includes script, "addEventListener('fetch'"
    assert_includes script, "index.html"
    assert_includes script, "<html><body><h1>Test App</h1></body></html>"
    assert_includes script, "console.log('Hello World');"
  end

  test "should return failure when credentials missing" do
    ENV.delete("CLOUDFLARE_API_TOKEN")

    result = @service.deploy!

    assert_not result[:success]
    assert_includes result[:error], "Missing Cloudflare credentials"
  end

  test "should generate app files as JSON correctly" do
    json_output = @service.send(:app_files_as_json)
    parsed = JSON.parse(json_output)

    assert_includes parsed, "index.html"
    assert_includes parsed, "script.js"
    assert_equal "<html><body><h1>Test App</h1></body></html>", parsed["index.html"]
    assert_equal "console.log('Hello World');", parsed["script.js"]
  end

  test "undeploy should succeed even when app not deployed" do
    result = @service.undeploy!

    assert result[:success]
    assert_equal "App not deployed", result[:message]
  end

  test "should handle special characters in app names" do
    # Create new app instead of updating existing one
    app = create(:app, name: "Test & Special! App @#$%")
    service = Deployment::CloudflareWorkerService.new(app)
    subdomain = service.send(:generate_subdomain)

    # Should only contain valid subdomain characters
    assert_match(/^[a-z0-9\-]+$/, subdomain)
    assert_includes subdomain, app.id.to_s
  end

  # Integration test would require actual Cloudflare API calls
  # For now, we'll test the structure and internal methods
  test "should have required methods for deployment" do
    assert_respond_to @service, :deploy!
    assert_respond_to @service, :undeploy!
  end
end
