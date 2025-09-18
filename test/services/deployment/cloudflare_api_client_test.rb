require "test_helper"
require "webmock/minitest"

class Deployment::CloudflareApiClientTest < ActiveSupport::TestCase
  setup do
    @app = apps(:one)
    @client = Deployment::CloudflareApiClient.new(@app)

    # Mock credentials
    Rails.application.credentials.stub :cloudflare, {
      account_id: "test_account",
      zone_id: "test_zone",
      api_token: "test_token",
      email: "test@example.com",
      r2_bucket: "test-bucket"
    } do
      @client = Deployment::CloudflareApiClient.new(@app)
    end
  end

  test "initializes with app and credentials" do
    assert_equal @app, @client.instance_variable_get(:@app)
    assert_equal "test_account", @client.instance_variable_get(:@account_id)
    assert_equal "test_zone", @client.instance_variable_get(:@zone_id)
    assert_equal "test_token", @client.instance_variable_get(:@api_token)
    assert_equal "test-bucket", @client.instance_variable_get(:@bucket_name)
  end

  test "generates consistent worker name" do
    worker_name = @client.send(:generate_worker_name)
    assert_equal "overskill-app-#{@app.id}", worker_name

    # Should be consistent across calls
    assert_equal worker_name, @client.send(:generate_worker_name)
  end

  test "validates worker script correctly" do
    # Valid script
    valid_script = "export default { fetch() {} }"
    assert_nothing_raised do
      @client.send(:validate_worker_script, valid_script)
    end

    # Empty script
    assert_raises Deployment::CloudflareApiClient::WorkerDeploymentError do
      @client.send(:validate_worker_script, "")
    end

    # Missing export
    assert_raises Deployment::CloudflareApiClient::WorkerDeploymentError do
      @client.send(:validate_worker_script, "function fetch() {}")
    end

    # Too large script
    huge_script = "export default { fetch() { return '#{" x" * 2.megabytes}' } }"
    assert_raises Deployment::CloudflareApiClient::WorkerDeploymentError do
      @client.send(:validate_worker_script, huge_script)
    end
  end

  test "deploy_worker makes correct API call" do
    worker_script = "export default { fetch() {} }"
    worker_name = "overskill-app-#{@app.id}"

    # Mock successful API response
    stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/test_account/workers/scripts/#{worker_name}")
      .with(
        body: worker_script,
        headers: {
          "Authorization" => "Bearer test_token",
          "Content-Type" => "application/javascript",
          "X-Auth-Email" => "test@example.com"
        }
      )
      .to_return(
        status: 200,
        body: {success: true, result: {id: "worker_123"}}.to_json
      )

    result = @client.deploy_worker(worker_script: worker_script)

    assert result[:success]
    assert_equal worker_name, result[:worker_name]
    assert_includes result[:worker_url], worker_name
    assert_equal "worker_123", result[:deployment_id]
  end

  test "upload_r2_assets handles multiple files" do
    r2_assets = {
      "app.js" => {content: 'console.log("app")', size: 18},
      "style.css" => {content: "body { margin: 0 }", size: 18}
    }

    # Mock R2 API calls
    r2_assets.each do |path, asset|
      object_key = "apps/#{@app.id}/#{path}"
      stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/test_account/r2/buckets/test-bucket/objects/#{object_key}")
        .to_return(status: 200, body: {success: true, result: {etag: "abc123"}}.to_json)
    end

    result = @client.upload_r2_assets(r2_assets)

    assert result[:success]
    assert_equal 2, result[:uploaded_files].size
    assert_empty result[:failed_files]
  end

  test "configure_worker_secrets sets environment variables" do
    worker_name = "overskill-app-#{@app.id}"

    # Create test env vars
    env_var = AppEnvVar.new(key: "TEST_KEY", value: "test_value", is_secret: true)
    @app.stub :app_env_vars, [env_var] do
      # Mock API calls
      stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/test_account/workers/scripts/#{worker_name}/secrets")
        .to_return(status: 200, body: {success: true}.to_json)

      result = @client.configure_worker_secrets

      assert result[:success]
      assert_includes result[:configured_secrets], "SUPABASE_URL"
      assert_includes result[:configured_secrets], "SUPABASE_SERVICE_KEY"
      assert_includes result[:configured_secrets], "APP_ID"
      assert_includes result[:configured_secrets], "TEST_KEY"
    end
  end

  test "configure_worker_routes creates routes" do
    @app.preview_url = "https://preview-#{@app.id}.overskill.app"
    @app.production_url = "https://app-#{@app.id}.overskill.app"

    # Mock route creation API calls
    stub_request(:post, "https://api.cloudflare.com/client/v4/zones/test_zone/workers/routes")
      .to_return(status: 200, body: {success: true, result: {id: "route_123"}}.to_json)

    result = @client.configure_worker_routes

    assert result[:success]
    assert_not_empty result[:configured_routes]
    assert result[:urls][:preview_url].present?
    assert result[:urls][:production_url].present?
  end

  test "deploy_complete_application orchestrates full deployment" do
    build_result = {
      worker_script: "export default { fetch() {} }",
      worker_size: 100_000,
      r2_assets: {
        "app.js" => {content: 'console.log("app")', size: 18}
      }
    }

    # Mock all API calls
    stub_cloudflare_apis

    result = @client.deploy_complete_application(build_result)

    assert result[:success]
    assert result[:worker_deployed]
    assert_not_empty result[:r2_assets]
    assert result[:secrets_configured]
    assert result[:routes_configured]
    assert result[:deployment_urls].present?
  end

  test "determines content types correctly" do
    assert_equal "application/javascript", @client.send(:determine_content_type, "app.js")
    assert_equal "text/css", @client.send(:determine_content_type, "style.css")
    assert_equal "text/html", @client.send(:determine_content_type, "index.html")
    assert_equal "application/json", @client.send(:determine_content_type, "data.json")
    assert_equal "image/png", @client.send(:determine_content_type, "logo.png")
    assert_equal "image/jpeg", @client.send(:determine_content_type, "photo.jpg")
    assert_equal "image/svg+xml", @client.send(:determine_content_type, "icon.svg")
    assert_equal "font/woff2", @client.send(:determine_content_type, "font.woff2")
  end

  test "handles API errors gracefully" do
    # Mock failed API response
    stub_request(:put, /api\.cloudflare\.com/)
      .to_return(
        status: 400,
        body: {
          success: false,
          errors: [{message: "Invalid worker script"}]
        }.to_json
      )

    assert_raises Deployment::CloudflareApiClient::WorkerDeploymentError do
      @client.deploy_worker(worker_script: "invalid")
    end
  end

  test "generates deployment URLs correctly" do
    routes = [
      {pattern: "preview-123.overskill.app/*", type: "preview"},
      {pattern: "app-123.overskill.app/*", type: "production"}
    ]

    urls = @client.send(:generate_deployment_urls, routes)

    assert_equal "https://preview-123.overskill.app", urls[:preview_url]
    assert_equal "https://app-123.overskill.app", urls[:production_url]
  end

  test "stores worker metadata in cache" do
    worker_name = "overskill-app-#{@app.id}"
    build_result = {
      mode: :production,
      worker_size: 800_000,
      r2_assets: {"app.js" => {}}
    }

    @client.send(:store_worker_metadata, worker_name, build_result)

    metadata = Rails.cache.read("app_#{@app.id}_worker_metadata")
    assert_not_nil metadata
    assert_equal worker_name, metadata[:worker_name]
    assert_equal :production, metadata[:build_mode]
    assert_equal 800_000, metadata[:worker_size]
    assert_equal 1, metadata[:r2_assets_count]
  end

  test "finalizes deployment updates app status" do
    deployment_result = {
      worker_deployed: true,
      deployment_urls: {
        preview_url: "https://preview.example.com",
        production_url: "https://prod.example.com"
      }
    }

    @client.send(:finalize_deployment, deployment_result)
    @app.reload

    assert_equal "deployed", @app.status
    assert_equal "https://preview.example.com", @app.preview_url
    assert_equal "https://prod.example.com", @app.production_url
    assert_not_nil @app.deployed_at
  end

  private

  def stub_cloudflare_apis
    # Stub all Cloudflare API endpoints for complete deployment
    worker_name = "overskill-app-#{@app.id}"

    # Worker deployment
    stub_request(:put, "https://api.cloudflare.com/client/v4/accounts/test_account/workers/scripts/#{worker_name}")
      .to_return(status: 200, body: {success: true, result: {id: "worker_123"}}.to_json)

    # R2 uploads
    stub_request(:put, /r2\/buckets/)
      .to_return(status: 200, body: {success: true, result: {etag: "abc123"}}.to_json)

    # Secrets
    stub_request(:put, /workers\/scripts\/.*\/secrets/)
      .to_return(status: 200, body: {success: true}.to_json)

    # Routes
    stub_request(:post, /workers\/routes/)
      .to_return(status: 200, body: {success: true, result: {id: "route_123"}}.to_json)
  end
end
