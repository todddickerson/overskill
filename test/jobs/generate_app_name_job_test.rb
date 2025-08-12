require "test_helper"
require "minitest/mock"

class GenerateAppNameJobTest < ActiveJob::TestCase
  setup do
    @team = create(:team)
    @app = create(:app, team: @team, name: "App #{rand(1000)}", prompt: "Create a todo list app for managing daily tasks")
  end

  test "should enqueue job" do
    assert_enqueued_with(job: GenerateAppNameJob) do
      GenerateAppNameJob.perform_later(@app.id)
    end
  end

  test "should be in default queue" do
    assert_equal "default", GenerateAppNameJob.new.queue_name
  end

  test "should skip generation if app has good name" do
    # Set a good, descriptive name
    @app.update!(name: "TaskFlow Pro", name_generated_at: 1.hour.ago)

    # Mock service to ensure it's not called
    service_called = false
    Ai::AppNamerService.stub :new, ->(*args) {
      service_called = true
      raise "Service should not be called for good names"
    } do
      GenerateAppNameJob.perform_now(@app.id)
    end

    assert_equal false, service_called, "Service should not be called for apps with good names"
  end

  test "should generate name for apps with generic names" do
    # Set a generic name that should trigger regeneration
    @app.update!(name: "App 123", name_generated_at: nil)

    # Track if the app.update method was called with name_generated_at
    updated_fields = {}
    
    # Mock successful name generation
    mock_service = Object.new
    def mock_service.generate_name!
      { success: true, old_name: "App 123", new_name: "TaskFlow", message: "App renamed to 'TaskFlow'" }
    end

    # Mock App.find to return our app with stubbed update method
    App.stub(:find, @app) do
      @app.stub(:update, ->(attrs) { 
        updated_fields.merge!(attrs)
        true
      }) do
        Ai::AppNamerService.stub(:new, mock_service) do
          GenerateAppNameJob.perform_now(@app.id)
        end
      end
    end

    # Verify the job tried to update name_generated_at
    assert updated_fields.key?(:name_generated_at), "Job should attempt to set name_generated_at"
    assert updated_fields[:name_generated_at].is_a?(Time), "name_generated_at should be a Time object"
  end

  test "should handle service failure gracefully" do
    @app.update!(name: "New App", name_generated_at: nil)

    # Mock failed name generation
    mock_service = Object.new
    def mock_service.generate_name!
      { success: false, error: "AI service unavailable", message: "Failed to generate app name" }
    end

    # Should not raise an exception
    assert_nothing_raised do
      Ai::AppNamerService.stub(:new, mock_service) do
        GenerateAppNameJob.perform_now(@app.id)
      end
    end
  end

  test "should handle exceptions during generation" do
    @app.update!(name: "Test App", name_generated_at: nil)

    # Mock service that raises an exception
    Ai::AppNamerService.stub :new, ->(*args) {
      raise StandardError, "Unexpected error"
    } do
      # Should not raise an exception due to rescue block
      assert_nothing_raised do
        GenerateAppNameJob.perform_now(@app.id)
      end
    end
  end

  test "should identify generic names correctly" do
    job = GenerateAppNameJob.new
    
    # Test generic patterns
    assert_equal false, job.send(:has_good_name?, create(:app, name: "App 123"))
    assert_equal false, job.send(:has_good_name?, create(:app, name: "New App"))
    assert_equal false, job.send(:has_good_name?, create(:app, name: "Untitled App"))
    assert_equal false, job.send(:has_good_name?, create(:app, name: "My App"))
    assert_equal false, job.send(:has_good_name?, create(:app, name: "Test App"))
    
    # Test good names
    assert_equal true, job.send(:has_good_name?, create(:app, name: "TaskFlow"))
    assert_equal true, job.send(:has_good_name?, create(:app, name: "Budget Tracker Pro"))
    assert_equal true, job.send(:has_good_name?, create(:app, name: "RecipeHub"))
    
    # Test recently generated names (should be kept)
    recent_app = create(:app, name: "Simple Name", name_generated_at: 1.hour.ago)
    assert_equal true, job.send(:has_good_name?, recent_app)
  end

  test "should find app by id" do
    # Test that job can find the app
    assert_nothing_raised do
      GenerateAppNameJob.perform_now(@app.id)
    end
  end

  test "should handle missing app gracefully" do
    # Test with non-existent app ID - the job should exit gracefully
    # without raising an exception (app was likely deleted)
    assert_nothing_raised do
      GenerateAppNameJob.perform_now(99999)
    end
  end
end
