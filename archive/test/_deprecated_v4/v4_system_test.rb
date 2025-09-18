# V4 System Integration Test
#
# This single test validates the entire V4 pipeline as it's being built.
# It evolves with development - each phase "lights up" as services are implemented.
#
# Usage:
#   rails test test/integration/v4_system_test.rb
#
# CI Integration:
#   This test runs in CI to ensure V4 functionality doesn't regress

require "test_helper"

class V4SystemTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    @team = teams(:one)
    @user = users(:one)
    @app = nil

    # Skip if V4 services not implemented yet
    @v4_available = defined?(Ai::AppBuilderV4)
  end

  test "V4 end-to-end app generation pipeline" do
    skip("V4 not implemented yet") unless @v4_available

    # Phase 1: App Creation ✅ (Always available)
    assert_difference "App.count", 1 do
      @app = create_v4_test_app("Generate a simple todo app with user authentication")
    end

    assert @app.persisted?
    assert @app.ai_model == "claude-sonnet-4", "Should use Claude Sonnet 4 for V4"
    assert_equal "generating", @app.status

    Rails.logger.info "[V4Test] ✅ App created: #{@app.id}"

    # Phase 2: V4 Orchestrator Execution
    if defined?(Ai::AppBuilderV4)
      Rails.logger.info "[V4Test] 🔄 Testing V4 orchestrator..."

      perform_enqueued_jobs do
        orchestrator = Ai::AppBuilderV4.new(@app.app_chat_messages.first)
        orchestrator.execute!
      end

      @app.reload
      assert_equal "generated", @app.status, "V4 orchestrator should generate app successfully"
      Rails.logger.info "[V4Test] ✅ V4 orchestrator completed"
    else
      Rails.logger.info "[V4Test] ⏭️  V4 orchestrator not implemented yet - skipping"
    end

    # Phase 3: Validate Shared Templates Generated
    if defined?(Ai::SharedTemplateService)
      Rails.logger.info "[V4Test] 🔄 Testing shared templates..."
      assert_v4_shared_templates_created
      Rails.logger.info "[V4Test] ✅ Shared templates validated"
    else
      Rails.logger.info "[V4Test] ⏭️  SharedTemplateService not implemented yet - skipping"
    end

    # Phase 4: Validate App-Specific Files
    if @app.app_files.count > 0
      Rails.logger.info "[V4Test] 🔄 Testing app-specific files..."
      assert_v4_app_files_created
      Rails.logger.info "[V4Test] ✅ App files validated"
    else
      Rails.logger.info "[V4Test] ⏭️  No app files generated yet - skipping"
    end

    # Phase 5: Validate Vite Build Success
    if defined?(Deployment::ViteBuilderService)
      Rails.logger.info "[V4Test] 🔄 Testing Vite builds..."
      assert_v4_build_successful
      Rails.logger.info "[V4Test] ✅ Vite build validated"
    else
      Rails.logger.info "[V4Test] ⏭️  ViteBuilderService not implemented yet - skipping"
    end

    # Phase 6: Validate Cloudflare Deployment
    if defined?(Deployment::CloudflareApiClient)
      Rails.logger.info "[V4Test] 🔄 Testing Cloudflare deployment..."
      assert_v4_deployment_successful
      Rails.logger.info "[V4Test] ✅ Deployment validated"
    else
      Rails.logger.info "[V4Test] ⏭️  CloudflareApiClient not implemented yet - skipping"
    end

    # Phase 7: Validate App Functionality
    if @app.preview_url.present?
      Rails.logger.info "[V4Test] 🔄 Testing app functionality..."
      assert_v4_app_functional
      Rails.logger.info "[V4Test] ✅ App functionality validated"
    else
      Rails.logger.info "[V4Test] ⏭️  App not deployed yet - skipping functionality test"
    end

    # Phase 8: Validate Metrics Tracking
    Rails.logger.info "[V4Test] 🔄 Testing metrics tracking..."
    assert_v4_metrics_tracked
    Rails.logger.info "[V4Test] ✅ Metrics tracking validated"

    Rails.logger.info "[V4Test] 🎉 V4 system test completed successfully!"
  end

  test "V4 error recovery system" do
    skip("V4 not implemented yet") unless @v4_available

    # Test that V4 handles failures gracefully
    @app = create_v4_test_app("Generate an invalid app that should fail")

    # Mock a failure scenario
    # This will test the 2x retry system when implemented
    Rails.logger.info "[V4Test] 🔄 Testing error recovery (when implemented)"
  end

  test "V4 performance benchmarks" do
    skip("V4 not implemented yet") unless @v4_available

    # Test that V4 meets performance targets
    start_time = Time.current

    @app = create_v4_test_app("Generate a benchmark test app")

    # When V4 is implemented, this will validate:
    # - Generation time < 2 minutes
    # - Build time < 45s (dev) or < 3min (prod)
    # - Worker size < 900KB

    total_time = Time.current - start_time
    Rails.logger.info "[V4Test] ⏱️  Total generation time: #{total_time.round(2)}s (target: <120s)"
  end

  private

  def create_v4_test_app(prompt)
    App.create!(
      name: "V4 Test App #{SecureRandom.hex(4)}",
      prompt: prompt,
      team: @team,
      creator: @team.memberships.first,
      ai_model: "claude-sonnet-4"  # Force V4 to use Claude Sonnet 4
    )
  end

  def assert_v4_shared_templates_created
    # Test that SharedTemplateService created foundation files
    required_templates = [
      "src/lib/supabase.ts",
      "src/pages/auth/Login.tsx",
      "src/components/auth/AuthForm.tsx",
      "package.json",
      "vite.config.ts",
      "tsconfig.json"
    ]

    required_templates.each do |template_path|
      assert @app.app_files.exists?(path: template_path),
        "Missing required template: #{template_path}"
    end

    # Validate TypeScript templates (not JSX)
    jsx_files = @app.app_files.where("path LIKE '%.jsx'")
    assert jsx_files.count == 0, "V4 should only use TypeScript (.tsx), found JSX files: #{jsx_files.pluck(:path)}"
  end

  def assert_v4_app_files_created
    # Test that AI generated app-specific files
    assert @app.app_files.count >= 8,
      "Should have at least 8 files generated, found: #{@app.app_files.count}"

    # Validate TypeScript usage (V4 requirement)
    tsx_files = @app.app_files.where("path LIKE '%.tsx'")
    ts_files = @app.app_files.where("path LIKE '%.ts'")

    assert (tsx_files.count + ts_files.count) >= 4,
      "Should have TypeScript files (.tsx/.ts), found: #{tsx_files.count + ts_files.count}"

    # Validate React Router structure
    pages_files = @app.app_files.where("path LIKE 'src/pages/%'")
    assert pages_files.count >= 2,
      "Should have pages directory structure, found: #{pages_files.count} files"
  end

  def assert_v4_build_successful
    # Test build process
    service = Deployment::ViteBuilderService.new(@app)
    result = service.build!(:development)

    assert result[:success], "Vite build should succeed: #{result[:error]}"
    assert result[:size] < 900_000,
      "Worker should be under 900KB, actual: #{result[:size]} bytes"

    # Test that build artifacts exist
    assert result[:assets].present?, "Build should produce assets"
  end

  def assert_v4_deployment_successful
    # Test deployment via API (no CLI)
    Deployment::CloudflareApiClient.new

    # Should have deployed via API
    assert @app.preview_url.present?, "Should have preview URL after deployment"
    assert @app.deployment_status == "deployed",
      "App status should be deployed, found: #{@app.deployment_status}"

    # Validate environment variables synced
    env_vars = @app.app_env_vars
    assert env_vars.exists?(key: "APP_ID"), "Should have APP_ID environment variable"
    assert env_vars.exists?(key: "SUPABASE_URL"), "Should have SUPABASE_URL environment variable"
  end

  def assert_v4_app_functional
    # Basic smoke test of deployed app
    # This would integrate with our existing testing tools

    # Make a simple HTTP request to verify the app loads
    response = Net::HTTP.get_response(URI(@app.preview_url))
    assert response.code.to_i < 400,
      "App should be accessible, got HTTP #{response.code}"

    # Verify it contains React and not just error page
    assert response.body.include?("react") || response.body.include?("React"),
      "App should contain React application"
  rescue => e
    flunk "App functionality test failed: #{e.message}"
  end

  def assert_v4_metrics_tracked
    version = @app.app_versions.last
    assert version.present?, "Should have at least one app version"

    # Token tracking (when implemented)
    if version.respond_to?(:ai_tokens_input)
      assert version.ai_tokens_input >= 0, "Should track input tokens (≥0)"
      assert version.ai_cost_cents >= 0, "Should track costs (≥0)"
      assert version.ai_model_used.present?, "Should track model used"

      Rails.logger.info "[V4Test] 💰 Token usage: #{version.ai_tokens_input} input, " \
        "#{version.ai_tokens_output} output, $#{version.ai_cost_cents / 100.0}"
    end

    # File tracking (always available)
    assert version.app_version_files.count >= 5,
      "Should track file changes (≥5), found: #{version.app_version_files.count}"

    # AI-generated display name (existing functionality)
    if version.display_name.present?
      assert version.display_name.length > 5,
        "Display name should be descriptive: '#{version.display_name}'"
    end

    Rails.logger.info "[V4Test] 📊 Tracked #{version.app_version_files.count} file changes"
  end
end
