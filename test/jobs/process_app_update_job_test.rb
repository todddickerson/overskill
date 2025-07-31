require "test_helper"
require "minitest/mock"

class ProcessAppUpdateJobTest < ActiveJob::TestCase
  setup do
    @app = create(:app, :generated)
    @chat_message = create(:app_chat_message, app: @app, role: "user", content: "Add a button", status: "pending")
  end

  test "should enqueue job" do
    assert_enqueued_with(job: ProcessAppUpdateJob) do
      ProcessAppUpdateJob.perform_later(@chat_message)
    end
  end

  test "should be in ai_generation queue" do
    assert_equal "ai_generation", ProcessAppUpdateJob.new.queue_name
  end

  test "should update chat message status to processing" do
    # Mock the AI client
    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, {
      success: true,
      content: '{"changes": {"summary": "Added button"}, "files": []}'
    }, [String, Array, Hash])

    Ai::OpenRouterClient.stub(:new, mock_client) do
      ProcessAppUpdateJob.perform_now(@chat_message)
    end

    @chat_message.reload
    assert_not_equal "pending", @chat_message.status
  end

  test "should create assistant response on success" do
    mock_response = {
      success: true,
      content: JSON.generate({
        changes: {
          summary: "Added a button to the interface",
          files_modified: ["index.html"]
        },
        files: [
          {
            action: "update",
            path: "index.html",
            content: "<button>Click me</button>"
          }
        ]
      })
    }

    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, mock_response, [String, Array, Hash])

    assert_difference "AppChatMessage.count", 1 do
      Ai::OpenRouterClient.stub(:new, mock_client) do
        ProcessAppUpdateJob.perform_now(@chat_message)
      end
    end

    assistant_message = AppChatMessage.last
    assert_equal "assistant", assistant_message.role
    assert_equal "completed", assistant_message.status
    assert_match "Added a button", assistant_message.content
  end

  test "should update existing files" do
    # Create existing file
    @app.app_files.create!(
      path: "index.html",
      content: "<h1>Original</h1>",
      file_type: "html",
      size_bytes: 17
    )

    mock_response = {
      success: true,
      content: JSON.generate({
        changes: {summary: "Updated HTML"},
        files: [
          {
            action: "update",
            path: "index.html",
            content: "<h1>Updated</h1><button>New Button</button>"
          }
        ]
      })
    }

    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, mock_response, [String, Array, Hash])

    Ai::OpenRouterClient.stub(:new, mock_client) do
      ProcessAppUpdateJob.perform_now(@chat_message)
    end

    file = @app.app_files.find_by(path: "index.html")
    assert_match "Updated", file.content
    assert_match "New Button", file.content
  end

  test "should create new files" do
    mock_response = {
      success: true,
      content: JSON.generate({
        changes: {summary: "Added new file"},
        files: [
          {
            action: "create",
            path: "new.js",
            content: "console.log('new file');",
            type: "javascript"
          }
        ]
      })
    }

    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, mock_response, [String, Array, Hash])

    assert_difference "AppFile.count", 1 do
      Ai::OpenRouterClient.stub(:new, mock_client) do
        ProcessAppUpdateJob.perform_now(@chat_message)
      end
    end

    new_file = AppFile.last
    assert_equal "new.js", new_file.path
    assert_equal "javascript", new_file.file_type
  end

  test "should delete files" do
    file = @app.app_files.create!(
      path: "to_delete.html",
      content: "Delete me",
      file_type: "html",
      size_bytes: 9
    )

    mock_response = {
      success: true,
      content: JSON.generate({
        changes: {summary: "Deleted file"},
        files: [
          {
            action: "delete",
            path: "to_delete.html"
          }
        ]
      })
    }

    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, mock_response, [String, Array, Hash])

    assert_difference "AppFile.count", -1 do
      Ai::OpenRouterClient.stub(:new, mock_client) do
        ProcessAppUpdateJob.perform_now(@chat_message)
      end
    end

    assert_nil AppFile.find_by(id: file.id)
  end

  test "should create app version" do
    mock_response = {
      success: true,
      content: JSON.generate({
        changes: {
          summary: "Updated app",
          files_modified: ["index.html"]
        },
        files: []
      })
    }

    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, mock_response, [String, Array, Hash])

    assert_difference "AppVersion.count", 1 do
      Ai::OpenRouterClient.stub(:new, mock_client) do
        ProcessAppUpdateJob.perform_now(@chat_message)
      end
    end

    version = AppVersion.last
    assert_equal "1.0.0", version.version_number
    assert_equal "Updated app", version.changes_summary
  end

  test "should handle AI error response" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, {
      success: false,
      error: "API rate limit exceeded"
    }, [String, Array, Hash])

    Ai::OpenRouterClient.stub(:new, mock_client) do
      ProcessAppUpdateJob.perform_now(@chat_message)
    end

    @chat_message.reload
    assert_equal "failed", @chat_message.status
    assert_equal "API rate limit exceeded", @chat_message.response

    # Should create error message
    error_message = AppChatMessage.last
    assert_equal "assistant", error_message.role
    assert_equal "failed", error_message.status
    assert_match "encountered an error", error_message.content
  end

  test "should broadcast updates via Turbo" do
    mock_response = {
      success: true,
      content: JSON.generate({
        changes: {summary: "Updated"},
        files: []
      })
    }

    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, mock_response, [String, Array, Hash])

    # Should broadcast processing, completion, and preview refresh
    assert_broadcasts("app_#{@app.id}_chat", 3) do
      Ai::OpenRouterClient.stub(:new, mock_client) do
        ProcessAppUpdateJob.perform_now(@chat_message)
      end
    end
  end

  test "should handle JSON parsing errors" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:update_app, {
      success: true,
      content: "Not valid JSON"
    }, [String, Array, Hash])

    Ai::OpenRouterClient.stub(:new, mock_client) do
      ProcessAppUpdateJob.perform_now(@chat_message)
    end

    @chat_message.reload
    assert_equal "failed", @chat_message.status
    assert_match "Failed to parse AI response", @chat_message.response
  end
end
