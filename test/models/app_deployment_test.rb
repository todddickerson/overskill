require "test_helper"

class AppDeploymentTest < ActiveSupport::TestCase
  setup do
    @team = create(:team)
    @membership = create(:membership, team: @team)
    @app = create(:app, team: @team, creator: @membership)
    # obfuscated_id is automatically set by BulletTrain
    
    @deployment = AppDeployment.create!(
      app: @app,
      environment: 'preview',
      deployment_id: "preview-#{@app.obfuscated_id}-1234567890",
      deployment_url: 'https://preview-test.workers.dev',
      deployed_at: Time.current
    )
  end

  test "should be valid with required attributes" do
    assert @deployment.valid?
  end

  test "should require app" do
    @deployment.app = nil
    assert_not @deployment.valid?
    assert_includes @deployment.errors[:app], "must exist"
  end

  test "should validate environment inclusion" do
    @deployment.environment = 'invalid'
    assert_not @deployment.valid?
    assert_includes @deployment.errors[:environment], "is not included in the list"
    
    %w[preview staging production].each do |env|
      @deployment.environment = env
      assert @deployment.valid?, "Should be valid with environment: #{env}"
    end
  end

  test "should enforce uniqueness of active deployment per environment" do
    # First deployment is already created in setup
    
    # Try to create another active deployment for same environment
    duplicate = AppDeployment.new(
      app: @app,
      environment: 'preview',
      deployment_id: "preview-#{@app.obfuscated_id}-9999999999",
      is_rollback: false
    )
    
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:environment], "can only have one active deployment per environment"
  end

  test "should allow multiple rollback deployments per environment" do
    # First mark the existing deployment as rollback so we can create more
    @deployment.update!(is_rollback: true)
    
    # Create rollback deployments - should be allowed
    rollback1 = AppDeployment.create!(
      app: @app,
      environment: 'preview',
      deployment_id: 'rollback-1',
      is_rollback: true,
      deployed_at: Time.current
    )
    
    rollback2 = AppDeployment.create!(
      app: @app,
      environment: 'preview',
      deployment_id: 'rollback-2',
      is_rollback: true,
      deployed_at: Time.current
    )
    
    assert rollback1.valid?
    assert rollback2.valid?
  end

  test "preview scope returns preview deployments" do
    AppDeployment.create!(
      app: @app,
      environment: 'staging',
      deployment_id: 'staging-123',
      deployed_at: Time.current
    )
    
    preview_deployments = AppDeployment.preview
    assert_includes preview_deployments, @deployment
    assert_equal 1, preview_deployments.where(environment: 'preview').count
  end

  test "staging scope returns staging deployments" do
    staging = AppDeployment.create!(
      app: @app,
      environment: 'staging',
      deployment_id: 'staging-123',
      deployed_at: Time.current
    )
    
    staging_deployments = AppDeployment.staging
    assert_includes staging_deployments, staging
    assert_not_includes staging_deployments, @deployment
  end

  test "production scope returns production deployments" do
    production = AppDeployment.create!(
      app: @app,
      environment: 'production',
      deployment_id: 'production-123',
      deployed_at: Time.current
    )
    
    production_deployments = AppDeployment.production
    assert_includes production_deployments, production
    assert_not_includes production_deployments, @deployment
  end

  test "active scope excludes rollback deployments" do
    rollback = AppDeployment.create!(
      app: @app,
      environment: 'staging',
      deployment_id: 'rollback-123',
      is_rollback: true,
      deployed_at: Time.current
    )
    
    active_deployments = AppDeployment.active
    assert_includes active_deployments, @deployment
    assert_not_includes active_deployments, rollback
  end

  test "rollbacks scope returns only rollback deployments" do
    rollback = AppDeployment.create!(
      app: @app,
      environment: 'staging',
      deployment_id: 'rollback-123',
      is_rollback: true,
      deployed_at: Time.current
    )
    
    rollback_deployments = AppDeployment.rollbacks
    assert_includes rollback_deployments, rollback
    assert_not_includes rollback_deployments, @deployment
  end

  test "recent scope orders by deployed_at descending" do
    older = AppDeployment.create!(
      app: @app,
      environment: 'staging',
      deployment_id: 'older',
      deployed_at: 2.days.ago
    )
    
    newer = AppDeployment.create!(
      app: @app,
      environment: 'production',
      deployment_id: 'newer',
      deployed_at: 1.hour.ago
    )
    
    recent = @app.app_deployments.recent
    assert_equal newer.id, recent.first.id
    assert_equal older.id, recent.last.id
  end

  test "chronological scope orders by deployed_at ascending" do
    older = AppDeployment.create!(
      app: @app,
      environment: 'staging',
      deployment_id: 'older',
      deployed_at: 2.days.ago
    )
    
    newer = AppDeployment.create!(
      app: @app,
      environment: 'production',
      deployment_id: 'newer',
      deployed_at: 1.hour.ago
    )
    
    chronological = @app.app_deployments.chronological
    assert_equal older.id, chronological.first.id
    assert_equal newer.id, chronological.last.id
  end

  test "rollback? returns true for rollback deployments" do
    @deployment.is_rollback = true
    assert @deployment.rollback?
    
    @deployment.is_rollback = false
    assert_not @deployment.rollback?
  end

  test "active_deployment? returns true for non-rollback deployments" do
    @deployment.is_rollback = false
    assert @deployment.active_deployment?
    
    @deployment.is_rollback = true
    assert_not @deployment.active_deployment?
  end

  test "environment helper methods work correctly" do
    # Preview deployment
    @deployment.environment = 'preview'
    assert @deployment.preview_deployment?
    assert_not @deployment.staging_deployment?
    assert_not @deployment.production_deployment?
    
    # Staging deployment
    @deployment.environment = 'staging'
    assert_not @deployment.preview_deployment?
    assert @deployment.staging_deployment?
    assert_not @deployment.production_deployment?
    
    # Production deployment
    @deployment.environment = 'production'
    assert_not @deployment.preview_deployment?
    assert_not @deployment.staging_deployment?
    assert @deployment.production_deployment?
  end

  test "create_for_environment! creates deployment with metadata" do
    deployment = AppDeployment.create_for_environment!(
      app: @app,
      environment: 'staging',
      deployment_id: 'staging-test-123',
      url: 'https://staging.example.com',
      commit_sha: 'abc123def'
    )
    
    assert deployment.persisted?
    assert_equal 'staging', deployment.environment
    assert_equal 'staging-test-123', deployment.deployment_id
    assert_equal 'https://staging.example.com', deployment.deployment_url
    assert_equal 'abc123def', deployment.commit_sha
    assert_not_nil deployment.deployed_at
    
    metadata = JSON.parse(deployment.deployment_metadata)
    assert_equal 'GitHub Migration System', metadata['deployed_by']
    assert_equal 'manual', metadata['deployment_type']
    assert_equal @app.obfuscated_id, metadata['app_obfuscated_id']
    assert_not_nil metadata['timestamp']
  end

  test "create_for_environment! auto-generates URL when not provided" do
    @app.update!(name: 'Test App')
    
    # Use a different environment or mark existing as rollback
    @deployment.update!(is_rollback: true)
    
    deployment = AppDeployment.create_for_environment!(
      app: @app,
      environment: 'preview',
      deployment_id: 'preview-auto-123'
    )
    
    expected_url = "https://preview-overskill-test-app-#{@app.obfuscated_id}.overskill.workers.dev"
    assert_equal expected_url, deployment.deployment_url
  end

  test "create_rollback! creates rollback deployment" do
    # Use a different environment to avoid conflict with setup deployment
    original = AppDeployment.create!(
      app: @app,
      environment: 'production',
      deployment_id: 'production-original',
      deployment_url: 'https://prod.example.com',
      commit_sha: 'original123',
      deployed_at: 1.day.ago
    )
    
    # Mark it as rollback first to allow creating another deployment in same environment
    original.update!(is_rollback: true)
    
    rollback = AppDeployment.create_rollback!(
      app: @app,
      environment: 'production',
      rollback_to_deployment: original,
      deployment_id: 'production-rollback-456'
    )
    
    assert rollback.persisted?
    assert rollback.is_rollback
    assert_equal 'production', rollback.environment
    assert_equal 'production-rollback-456', rollback.deployment_id
    assert_equal original.deployment_url, rollback.deployment_url
    assert_equal original.commit_sha, rollback.commit_sha
    assert_equal original.id.to_s, rollback.rollback_version_id
    
    metadata = JSON.parse(rollback.deployment_metadata)
    assert_equal original.id, metadata['rollback_to']
    assert_equal 'rollback', metadata['deployment_type']
    assert_equal @app.obfuscated_id, metadata['app_obfuscated_id']
  end

  test "generate_environment_url uses obfuscated_id" do
    @app.update!(name: 'My Cool App')
    
    # Test private class method
    url = AppDeployment.send(:generate_environment_url, @app, 'preview')
    assert_equal "https://preview-overskill-my-cool-app-#{@app.obfuscated_id}.overskill.workers.dev", url
    
    url = AppDeployment.send(:generate_environment_url, @app, 'staging')
    assert_equal "https://staging-overskill-my-cool-app-#{@app.obfuscated_id}.overskill.workers.dev", url
    
    url = AppDeployment.send(:generate_environment_url, @app, 'production')
    assert_equal "https://overskill-my-cool-app-#{@app.obfuscated_id}.overskill.workers.dev", url
  end
end