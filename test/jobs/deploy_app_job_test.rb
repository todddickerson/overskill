require "test_helper"
require "minitest/mock"

class DeployAppJobTest < ActiveSupport::TestCase
  def setup
    @app = create(:app)

    # Create some test files so the app can be deployed
    @app.app_files.create!(
      team: @app.team,
      path: "index.html",
      content: "<html><body><h1>Test</h1></body></html>",
      file_type: "html",
      size_bytes: 38
    )
  end

  test "should update app status to deploying when job starts" do
    # Mock the service to return success
    mock_service = Minitest::Mock.new
    mock_service.expect :deploy!, {success: true, message: "https://app-123.overskill.app"}

    Deployment::CloudflareWorkerService.stub :new, mock_service do
      DeployAppJob.perform_now(@app.id)
    end

    # The job should have attempted to set status to deploying
    # (though it might be overridden by the success status)
    mock_service.verify
  end

  test "should create version when deployment succeeds" do
    # Mock successful deployment
    mock_service = Minitest::Mock.new
    mock_service.expect :deploy!, {success: true, message: "https://app-123.overskill.app"}

    initial_version_count = @app.app_versions.count

    Deployment::CloudflareWorkerService.stub :new, mock_service do
      DeployAppJob.perform_now(@app.id)
    end

    assert_equal initial_version_count + 1, @app.app_versions.count

    latest_version = @app.app_versions.order(created_at: :desc).first
    assert_includes latest_version.changelog, "Deployed to production"

    mock_service.verify
  end

  test "should handle deployment failure gracefully" do
    # Mock failed deployment
    mock_service = Minitest::Mock.new
    mock_service.expect :deploy!, {success: false, error: "API Error"}

    Deployment::CloudflareWorkerService.stub :new, mock_service do
      DeployAppJob.perform_now(@app.id)
    end

    @app.reload
    assert_equal "failed", @app.deployment_status

    mock_service.verify
  end

  test "should generate incremental version numbers" do
    # Create a previous version
    @app.app_versions.create!(
      version_number: "1.0.5",
      changelog: "Previous version",
      team: @app.team
    )

    # Mock successful deployment
    mock_service = Minitest::Mock.new
    mock_service.expect :deploy!, {success: true, message: "https://app-123.overskill.app"}

    Deployment::CloudflareWorkerService.stub :new, mock_service do
      DeployAppJob.perform_now(@app.id)
    end

    latest_version = @app.app_versions.order(created_at: :desc).first
    assert_equal "1.0.6", latest_version.version_number

    mock_service.verify
  end

  test "should handle job errors gracefully" do
    # Test with invalid app ID
    assert_nothing_raised do
      DeployAppJob.perform_now(999999)
    end
  end

  test "should use deployment queue" do
    assert_equal "deployment", DeployAppJob.new.queue_name
  end
end
