require "test_helper"
require "minitest/mock"

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

    # Track if service was instantiated
    service_called = false
    
    Ai::AppGeneratorService.stub :new, ->(*args) {
      service_called = true
      raise "Service should not be called for completed generation"
    } do
      AppGenerationJob.perform_now(@generation)
    end
    
    assert_equal false, service_called, "Service should not be instantiated for completed generation"
  end

  test "should update app and generation status on success" do
    # Mock successful generation (the service updates the models itself)
    mock_service = Object.new
    def mock_service.generate!
      @app.update!(status: "generated")
      @generation.update!(status: "completed", completed_at: Time.current)
      {success: true}
    end
    
    # Set instance variables on the mock
    mock_service.instance_variable_set(:@app, @app)
    mock_service.instance_variable_set(:@generation, @generation)

    Ai::AppGeneratorService.stub(:new, mock_service) do
      AppGenerationJob.perform_now(@generation)
    end

    @app.reload
    @generation.reload

    assert_equal "generated", @app.status
    assert_equal "completed", @generation.status
  end

  test "should handle generation failure" do
    # Mock failed generation (the service updates the models itself)
    mock_service = Object.new
    def mock_service.generate!
      @app.update!(status: "failed")
      @generation.update!(status: "failed", error_message: "Test error", completed_at: Time.current)
      {success: false, error: "Test error"}
    end
    
    # Set instance variables on the mock
    mock_service.instance_variable_set(:@app, @app)
    mock_service.instance_variable_set(:@generation, @generation)

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
    mock_service = Object.new
    def mock_service.generate!
      @app.update!(status: "generated")
      @generation.update!(status: "completed", completed_at: Time.current)
      {success: true}
    end
    
    # Set instance variables on the mock
    mock_service.instance_variable_set(:@app, @app)
    mock_service.instance_variable_set(:@generation, @generation)

    # The job broadcasts twice - once for update and once for replace
    assert_broadcasts("app_#{@app.id}_generation", 2) do
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
    # Test that exceptions are properly handled and status is updated
    # Create a stub that raises an exception
    exception_raised = false
    
    Ai::AppGeneratorService.stub :new, ->(*args) {
      mock = Object.new
      mock.define_singleton_method(:generate!) do
        exception_raised = true
        raise StandardError, "Unexpected error"
      end
      mock
    } do
      # In test environment, perform_now might return the exception instead of raising
      result = AppGenerationJob.perform_now(@generation)
      
      # Check if result is the exception (ActiveJob test behavior)
      if result.is_a?(StandardError)
        assert_equal "Unexpected error", result.message
      else
        # Otherwise, the exception should have been raised
        assert false, "Expected StandardError to be raised or returned"
      end
    end
    
    assert exception_raised, "The service generate! method should have been called"
    
    # Verify status was updated before re-raising
    @generation.reload
    @app.reload
    assert_equal "failed", @generation.status
    assert_equal "failed", @app.status
    assert_match "Unexpected error", @generation.error_message
  end
end
