require "test_helper"

class AppGithubMigrationTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @membership = create(:membership, team: @team)
    @app = create(:app,
      team: @team,
      creator: @membership,
      name: "Test App",
      subdomain: "test-app-migration")
    # obfuscated_id is automatically set by BulletTrain

    # Mock environment variables
    ENV["GITHUB_TOKEN"] = "test_token"
    ENV["GITHUB_ORG"] = "Overskill-apps"
    ENV["CLOUDFLARE_API_TOKEN"] = "test_cf_token"
    ENV["CLOUDFLARE_ACCOUNT_ID"] = "test_account_id"
  end

  teardown do
    ENV.delete("GITHUB_TOKEN")
    ENV.delete("GITHUB_ORG")
    ENV.delete("CLOUDFLARE_API_TOKEN")
    ENV.delete("CLOUDFLARE_ACCOUNT_ID")
  end

  test "repository_status enum is properly defined" do
    @app.repository_status = "pending"
    assert @app.repository_pending?

    @app.repository_status = "creating"
    assert @app.repository_creating?

    @app.repository_status = "ready"
    assert @app.repository_ready?

    @app.repository_status = "failed"
    assert @app.repository_failed?
  end

  test "using_repository_mode? detects repository mode" do
    # Initially should not be in repository mode
    assert_not @app.using_repository_mode?

    # With only repository_name
    @app.repository_name = "test-repo"
    assert_not @app.using_repository_mode?

    # With both repository_name and repository_url
    @app.repository_url = "https://github.com/Overskill-apps/test-repo"
    assert @app.using_repository_mode?
  end

  test "using_legacy_mode? detects legacy mode" do
    # Create app_files for legacy mode
    @app.app_files.create!(
      path: "test.js",
      content: 'console.log("test")',
      team: @app.team,
      file_type: "javascript"
    )

    # Should be in legacy mode
    assert @app.using_legacy_mode?

    # Switch to repository mode
    @app.update!(
      repository_name: "test-repo",
      repository_url: "https://github.com/Overskill-apps/test-repo"
    )

    # Should not be in legacy mode anymore
    assert_not @app.using_legacy_mode?
  end

  test "deployment_environments returns correct URLs" do
    @app.update!(
      preview_url: "https://preview.example.com",
      staging_url: "https://staging.example.com",
      production_url: "https://production.example.com"
    )

    envs = @app.deployment_environments

    assert_equal "https://preview.example.com", envs[:preview]
    assert_equal "https://staging.example.com", envs[:staging]
    assert_equal "https://production.example.com", envs[:production]
  end

  test "deployment_environments excludes nil URLs" do
    @app.update!(
      preview_url: "https://preview.example.com",
      staging_url: nil,
      production_url: nil
    )

    envs = @app.deployment_environments

    assert_equal 1, envs.size
    assert_equal "https://preview.example.com", envs[:preview]
    assert_nil envs[:staging]
    assert_nil envs[:production]
  end

  test "can_promote_to_staging? checks prerequisites" do
    # Missing repository ready status
    @app.repository_status = "pending"
    assert_not @app.can_promote_to_staging?

    # Repository ready but no preview URL
    @app.repository_status = "ready"
    @app.preview_url = nil
    assert_not @app.can_promote_to_staging?

    # All prerequisites met
    @app.preview_url = "https://preview.example.com"
    @app.deployment_status = "preview_deployed"
    assert @app.can_promote_to_staging?

    # Failed deployment status blocks promotion
    @app.deployment_status = "failed"
    assert_not @app.can_promote_to_staging?
  end

  test "can_promote_to_production? checks prerequisites" do
    # Missing staging deployment
    @app.staging_deployed_at = nil
    assert_not @app.can_promote_to_production?

    # Staging deployed but no URL
    @app.staging_deployed_at = 1.hour.ago
    @app.staging_url = nil
    assert_not @app.can_promote_to_production?

    # All prerequisites met
    @app.staging_url = "https://staging.example.com"
    @app.deployment_status = "staging_deployed"
    assert @app.can_promote_to_production?

    # Failed deployment status blocks promotion
    @app.deployment_status = "failed"
    assert_not @app.can_promote_to_production?
  end

  test "github_repository_service returns service instance" do
    service = @app.github_repository_service
    assert_instance_of Deployment::GitHubRepositoryService, service

    # Should return same instance on subsequent calls
    assert_equal service.object_id, @app.github_repository_service.object_id
  end

  test "cloudflare_workers_service returns service instance" do
    service = @app.cloudflare_workers_service
    assert_instance_of Deployment::CloudflareWorkersBuildService, service

    # Should return same instance on subsequent calls
    assert_equal service.object_id, @app.cloudflare_workers_service.object_id
  end

  test "generate_worker_name uses obfuscated_id" do
    worker_name = @app.generate_worker_name

    assert_includes worker_name, @app.obfuscated_id
    assert_match(/^overskill-[a-z\-]+-[\w]+$/, worker_name)
    assert_equal "overskill-test-app-#{@app.obfuscated_id}", worker_name
  end

  test "generate_repository_name uses obfuscated_id" do
    repo_name = @app.generate_repository_name

    assert_includes repo_name, @app.obfuscated_id
    assert_match(/^[a-z\-]+-[\w]+$/, repo_name)
    assert_equal "test-app-#{@app.obfuscated_id}", repo_name
  end

  test "generate_worker_name handles special characters in name" do
    @app.update!(name: "My Cool App!")
    worker_name = @app.generate_worker_name

    assert_equal "overskill-my-cool-app-#{@app.obfuscated_id}", worker_name
  end

  test "create_repository_via_fork! success scenario" do
    # Mock successful GitHub service response
    mock_github_result = {
      success: true,
      repo_name: "test-app-#{@app.obfuscated_id}",
      repository: {"name" => "test-app-#{@app.obfuscated_id}"}
    }

    # Mock successful Cloudflare service response
    mock_cf_result = {
      success: true,
      worker_name: "overskill-test-app-#{@app.obfuscated_id}",
      preview_url: "https://preview.workers.dev",
      staging_url: "https://staging.workers.dev",
      production_url: "https://production.workers.dev"
    }

    Deployment::GithubRepositoryService.any_instance.stubs(:create_app_repository_via_fork).returns(mock_github_result)
    Deployment::CloudflareWorkersBuildService.any_instance.stubs(:create_worker_with_git_integration).returns(mock_cf_result)

    result = @app.create_repository_via_fork!

    assert result[:success]
    assert_equal "overskill-test-app-#{@app.obfuscated_id}", result[:worker_name]

    @app.reload
    assert_equal "overskill-test-app-#{@app.obfuscated_id}", @app.cloudflare_worker_name
    assert_equal "https://preview.workers.dev", @app.preview_url
    assert_equal "https://staging.workers.dev", @app.staging_url
    assert_equal "https://production.workers.dev", @app.production_url
    assert_equal "preview_building", @app.deployment_status
  end

  test "create_repository_via_fork! handles GitHub failure" do
    # Mock failed GitHub service response
    mock_github_result = {
      success: false,
      error: "Repository creation failed"
    }

    Deployment::GithubRepositoryService.any_instance.stubs(:create_app_repository_via_fork).returns(mock_github_result)

    result = @app.create_repository_via_fork!

    assert_not result[:success]
    assert_equal "Repository creation failed", result[:error]

    @app.reload
    assert_equal "failed", @app.repository_status
  end

  test "promote_to_staging! creates deployment record" do
    @app.update!(
      repository_status: "ready",
      preview_url: "https://preview.example.com",
      staging_url: "https://staging.example.com",
      cloudflare_worker_name: "test-worker"
    )

    mock_result = {
      success: true,
      deployment_id: "staging-#{@app.obfuscated_id}-123456"
    }

    Deployment::CloudflareWorkersBuildService.any_instance.stubs(:promote_to_staging).returns(mock_result)

    assert_difference "AppDeployment.count", 1 do
      result = @app.promote_to_staging!
      assert result[:success]
    end

    @app.reload
    assert_equal "staging_deployed", @app.deployment_status
    assert_not_nil @app.staging_deployed_at

    deployment = @app.app_deployments.last
    assert_equal "staging", deployment.environment
    assert_equal "staging-#{@app.obfuscated_id}-123456", deployment.deployment_id
    assert_equal "https://staging.example.com", deployment.deployment_url
  end

  test "promote_to_staging! blocks when prerequisites not met" do
    @app.update!(repository_status: "pending")

    result = @app.promote_to_staging!

    assert_not result[:success]
    assert_equal "Cannot promote to staging", result[:error]
  end

  test "promote_to_production! creates deployment record" do
    @app.update!(
      staging_deployed_at: 1.hour.ago,
      staging_url: "https://staging.example.com",
      production_url: "https://production.example.com",
      cloudflare_worker_name: "test-worker"
    )

    mock_result = {
      success: true,
      deployment_id: "production-#{@app.obfuscated_id}-123456"
    }

    Deployment::CloudflareWorkersBuildService.any_instance.stubs(:promote_to_production).returns(mock_result)

    assert_difference "AppDeployment.count", 1 do
      result = @app.promote_to_production!
      assert result[:success]
    end

    @app.reload
    assert_equal "production_deployed", @app.deployment_status
    assert_equal "published", @app.status
    assert_not_nil @app.last_deployed_at

    deployment = @app.app_deployments.last
    assert_equal "production", deployment.environment
    assert_equal "production-#{@app.obfuscated_id}-123456", deployment.deployment_id
    assert_equal "https://production.example.com", deployment.deployment_url
  end

  test "promote_to_production! blocks when prerequisites not met" do
    @app.update!(staging_deployed_at: nil)

    result = @app.promote_to_production!

    assert_not result[:success]
    assert_equal "Cannot promote to production", result[:error]
  end

  test "get_deployment_status uses cloudflare service for repository mode" do
    @app.update!(
      repository_name: "test-repo",
      repository_url: "https://github.com/Overskill-apps/test-repo"
    )

    mock_status = {
      success: true,
      environments: {
        preview: {status: "deployed"},
        staging: {status: "not_deployed"},
        production: {status: "not_deployed"}
      }
    }

    Deployment::CloudflareWorkersBuildService.any_instance.stubs(:get_deployment_status).returns(mock_status)

    status = @app.get_deployment_status

    assert status[:success]
    assert_equal "deployed", status[:environments][:preview][:status]
  end

  test "get_deployment_status returns legacy status for non-repository apps" do
    @app.update!(
      preview_url: "https://preview.example.com",
      staging_url: "https://staging.example.com",
      staging_deployed_at: 1.hour.ago,
      deployment_status: "production_deployed"
    )

    # Create app_file to ensure legacy mode
    @app.app_files.create!(
      path: "test.js",
      content: "test",
      team: @app.team,
      file_type: "javascript"
    )

    status = @app.get_deployment_status

    assert status[:success]
    assert status[:legacy_mode]
    assert_equal "https://preview.example.com", status[:environments][:preview][:url]
    assert_equal "deployed", status[:environments][:preview][:status]
    assert_equal "deployed", status[:environments][:staging][:status]
    assert_equal "deployed", status[:environments][:production][:status]
  end
end
