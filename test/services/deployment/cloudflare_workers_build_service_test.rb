require "test_helper"

class Deployment::CloudflareWorkersBuildServiceTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @membership = create(:membership, team: @team)
    @app = create(:app, team: @team, creator: @membership, name: "Test App")
    # obfuscated_id is automatically set by BulletTrain

    # Mock environment variables
    ENV["CLOUDFLARE_API_TOKEN"] = "test_cf_token"
    ENV["CLOUDFLARE_ACCOUNT_ID"] = "test_account_id"
    ENV["GITHUB_ORG"] = "Overskill-apps"
    ENV["SUPABASE_URL"] = "https://test.supabase.co"
    ENV["SUPABASE_ANON_KEY"] = "test_anon_key"

    @service = Deployment::CloudflareWorkersBuildService.new(@app)

    @repo_result = {
      success: true,
      repo_name: "test-app-#{@app.obfuscated_id}",
      repository: {"name" => "test-app-#{@app.obfuscated_id}"}
    }
  end

  teardown do
    ENV.delete("CLOUDFLARE_API_TOKEN")
    ENV.delete("CLOUDFLARE_ACCOUNT_ID")
    ENV.delete("GITHUB_ORG")
    ENV.delete("SUPABASE_URL")
    ENV.delete("SUPABASE_ANON_KEY")
  end

  test "should initialize with required environment variables" do
    assert_not_nil @service
  end

  test "should raise error when Cloudflare credentials missing" do
    ENV.delete("CLOUDFLARE_API_TOKEN")

    assert_raises(RuntimeError) do
      Deployment::CloudflareWorkersBuildService.new(@app)
    end
  end

  test "generate_worker_name uses obfuscated_id for privacy" do
    worker_name = @service.send(:generate_worker_name)

    assert_includes worker_name, @app.obfuscated_id
    assert_match(/^overskill-[\w-]+-[\w]+$/, worker_name)
    assert_equal "overskill-test-app-#{@app.obfuscated_id}", worker_name
  end

  test "generate URLs with correct patterns" do
    worker_name = @service.send(:generate_worker_name)

    preview_url = @service.send(:generate_preview_url, worker_name)
    assert_equal "https://preview-overskill-test-app-#{@app.obfuscated_id}.overskill.workers.dev", preview_url

    staging_url = @service.send(:generate_staging_url, worker_name)
    assert_equal "https://staging-overskill-test-app-#{@app.obfuscated_id}.overskill.workers.dev", staging_url

    production_url = @service.send(:generate_production_url, worker_name)
    assert_equal "https://overskill-test-app-#{@app.obfuscated_id}.overskill.workers.dev", production_url
  end

  test "create_worker_with_git_integration success scenario" do
    # Mock successful worker creation
    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      "result" => {"id" => "worker_123"}
    })

    @service.class.stubs(:put).returns(mock_response)
    @service.stubs(:setup_worker_environment_variables).returns({success: true})
    @service.stubs(:setup_worker_domains).returns({success: true})

    result = @service.create_worker_with_git_integration(@repo_result)

    assert result[:success]
    assert_equal "overskill-test-app-#{@app.obfuscated_id}", result[:worker_name]
    assert_not_nil result[:preview_url]
    assert_not_nil result[:staging_url]
    assert_not_nil result[:production_url]
    assert result[:git_integration]
    assert_equal "Push to 'main' branch", result[:auto_deploy][:preview]
    assert_equal "Manual promotion", result[:auto_deploy][:staging]
  end

  test "create_worker_with_git_integration handles failure" do
    # Mock failed worker creation
    mock_response = mock
    mock_response.stubs(:success?).returns(false)
    mock_response.stubs(:code).returns(400)
    mock_response.stubs(:body).returns("Invalid configuration")

    @service.class.stubs(:put).returns(mock_response)

    result = @service.create_worker_with_git_integration(@repo_result)

    assert_not result[:success]
    assert_equal "Worker creation failed: 400", result[:error]
  end

  test "promote_to_staging updates app status" do
    @app.update!(cloudflare_worker_name: "test-worker")

    @service.stubs(:trigger_environment_deployment).returns({
      success: true,
      deployment_id: "staging-#{@app.obfuscated_id}-123456"
    })

    # Mock AppDeployment creation
    AppDeployment.stubs(:create!).returns(true)

    result = @service.promote_to_staging

    assert result[:success]
    assert_equal "staging-#{@app.obfuscated_id}-123456", result[:deployment_id]

    @app.reload
    assert_equal "staging_deployed", @app.deployment_status
    assert_not_nil @app.staging_deployed_at
  end

  test "promote_to_production updates app status" do
    @app.update!(cloudflare_worker_name: "test-worker")

    @service.stubs(:trigger_environment_deployment).returns({
      success: true,
      deployment_id: "production-#{@app.obfuscated_id}-123456"
    })

    # Mock AppDeployment creation
    AppDeployment.stubs(:create!).returns(true)

    result = @service.promote_to_production

    assert result[:success]
    assert_equal "production-#{@app.obfuscated_id}-123456", result[:deployment_id]

    @app.reload
    assert_equal "production_deployed", @app.deployment_status
    assert_not_nil @app.last_deployed_at
  end

  test "promote methods fail when no worker configured" do
    @app.update!(cloudflare_worker_name: nil)

    result = @service.promote_to_staging
    assert_not result[:success]
    assert_equal "No worker configured", result[:error]

    result = @service.promote_to_production
    assert_not result[:success]
    assert_equal "No worker configured", result[:error]
  end

  test "get_deployment_status returns comprehensive status" do
    @app.update!(
      cloudflare_worker_name: "test-worker",
      preview_url: "https://preview-test.workers.dev",
      staging_url: "https://staging-test.workers.dev",
      production_url: "https://test.workers.dev",
      staging_deployed_at: 1.day.ago,
      deployment_status: "production_deployed",
      last_deployed_at: 1.hour.ago
    )

    mock_response = mock
    mock_response.stubs(:success?).returns(true)
    mock_response.stubs(:parsed_response).returns({
      "result" => {
        "modified_on" => Time.current.iso8601
      }
    })

    @service.class.stubs(:get).returns(mock_response)

    result = @service.get_deployment_status

    assert result[:success]
    assert_equal "test-worker", result[:worker_name]

    # Check preview environment
    assert_equal "https://preview-test.workers.dev", result[:environments][:preview][:url]
    assert_equal "active", result[:environments][:preview][:status]

    # Check staging environment
    assert_equal "https://staging-test.workers.dev", result[:environments][:staging][:url]
    assert_equal "deployed", result[:environments][:staging][:status]
    assert_not_nil result[:environments][:staging][:last_deployed]

    # Check production environment
    assert_equal "https://test.workers.dev", result[:environments][:production][:url]
    assert_equal "deployed", result[:environments][:production][:status]
    assert_not_nil result[:environments][:production][:last_deployed]
  end

  test "setup_worker_environment_variables sets correct values" do
    worker_name = "test-worker"

    # Track PUT calls
    put_calls = []
    @service.class.stubs(:put).with do |url, options|
      put_calls << options[:body]
      true
    end.returns(mock(success?: true))

    result = @service.send(:setup_worker_environment_variables, worker_name)

    assert result[:success]
    assert_equal 5, result[:variables_set]

    # Verify obfuscated_id is used for APP_ID
    app_id_call = put_calls.find { |call| JSON.parse(call)["name"] == "VITE_APP_ID" }
    assert_equal @app.obfuscated_id, JSON.parse(app_id_call)["text"]
  end

  test "trigger_environment_deployment generates unique deployment_id" do
    worker_name = "test-worker"
    environment = "staging"

    mock_response = mock
    mock_response.stubs(:success?).returns(true)

    @service.class.stubs(:post).returns(mock_response)

    result = @service.send(:trigger_environment_deployment, worker_name, environment)

    assert result[:success]
    assert_match(/^staging-#{Regexp.escape(@app.obfuscated_id)}-\d+$/, result[:deployment_id])
    assert_equal "staging", result[:environment]
    assert_not_nil result[:triggered_at]
  end

  test "generate_build_worker_script returns ES module format" do
    script = @service.send(:generate_build_worker_script)

    assert_includes script, "export default"
    assert_includes script, "async fetch(request, env, ctx)"
    assert_includes script, "OverSkill App - Building..."
  end
end
