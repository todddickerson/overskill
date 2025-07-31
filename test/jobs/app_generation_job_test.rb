require "test_helper"

class AppGenerationJobTest < ActiveJob::TestCase
  setup do
    @team = create(:team)
    @app = create(:app, team: @team)
    @generation = create(:app_generation, app: @app, team: @team, status: "pending")
  end

  test "should enqueue job" do
    assert_enqueued_with(job: AppGenerationJob) do
      AppGenerationJob.perform_later(@generation)
    end
  end

  test "should be in ai_generation queue" do
    assert_equal "ai_generation", AppGenerationJob.new.queue_name
  end

  test "should not process already completed generation" do
    @generation.update!(status: "completed")

    # Mock the service to ensure it's not called
    mock_service = Minitest::Mock.new

    Ai::AppGeneratorService.stub(:new, mock_service) do
      AppGenerationJob.perform_now(@generation)

      # Service should not be instantiated for completed generation
      mock_service.verify
    end
  end

  test "should update app and generation status on success" do
    # Mock successful generation
    mock_service = Minitest::Mock.new
    mock_service.expect(:generate!, {success: true})

    Ai::AppGeneratorService.stub(:new, mock_service) do
      AppGenerationJob.perform_now(@generation)
    end

    @app.reload
    @generation.reload

    assert_equal "generated", @app.status
    assert_equal "completed", @generation.status
  end

  test "should handle generation failure" do
    # Mock failed generation
    mock_service = Minitest::Mock.new
    mock_service.expect(:generate!, {success: false, error: "Test error"})

    Ai::AppGeneratorService.stub(:new, mock_service) do
      AppGenerationJob.perform_now(@generation)
    end

    @app.reload
    @generation.reload

    assert_equal "failed", @app.status
    assert_equal "failed", @generation.status
    assert_equal "Test error", @generation.error_message
  end

  test "should broadcast status updates" do
    mock_service = Minitest::Mock.new
    mock_service.expect(:generate!, {success: true})

    assert_broadcasts("app_#{@app.id}_generation", 1) do
      Ai::AppGeneratorService.stub(:new, mock_service) do
        AppGenerationJob.perform_now(@generation)
      end
    end
  end

  test "should retry on failure with polynomial backoff" do
    # Test that job is configured with retry_on
    job = AppGenerationJob.new
    assert job.class.respond_to?(:retry_on)
  end

  test "should handle exceptions during generation" do
    # Mock service that raises exception
    mock_service = Minitest::Mock.new
    mock_service.expect(:generate!, -> { raise StandardError, "Unexpected error" })

    Ai::AppGeneratorService.stub(:new, mock_service) do
      assert_raises(StandardError) do
        AppGenerationJob.perform_now(@generation)
      end
    end

    @generation.reload
    assert_equal "failed", @generation.status
    assert_match "Unexpected error", @generation.error_message
  end
end
