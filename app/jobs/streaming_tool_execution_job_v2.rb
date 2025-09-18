# Improved Sidekiq job for streaming tool execution with better status updates
class StreamingToolExecutionJobV2 < ApplicationJob
  queue_as :tools

  # Add timeout to prevent jobs from running forever
  sidekiq_options retry: 3, dead: false, timeout_in: 120

  def perform(message_id, execution_id, tool_index, tool_call, iteration_count = 0)
    @message = AppChatMessage.find(message_id)
    @app = @message.app
    @execution_id = execution_id
    @tool_index = tool_index
    @iteration_count = iteration_count

    # Handle both string and symbol keys for compatibility
    tool_call = tool_call.deep_stringify_keys if tool_call.is_a?(Hash)

    tool_name = tool_call["function"]["name"]
    begin
      JSON.parse(tool_call["function"]["arguments"])
    rescue
      {}
    end

    Rails.logger.info "[V2_TOOL_JOB] Executing #{tool_name} (#{tool_index}) in execution #{execution_id}"

    # Update status to running immediately with retry logic
    update_status_with_retry("running")

    begin
      # Use the existing StreamingToolExecutor for compatibility
      executor = Ai::StreamingToolExecutor.new(@message, @app, @iteration_count)
      result = executor.execute_with_streaming(tool_call, tool_index)

      Rails.logger.info "[V2_TOOL_JOB] Tool #{tool_name} completed successfully"

      # Report success back to coordinator
      Ai::StreamingToolCoordinatorV2.tool_completed(
        message_id,
        execution_id,
        tool_index,
        result,
        nil
      )
    rescue => e
      Rails.logger.error "[V2_TOOL_JOB] Failed #{tool_name} (#{tool_index}): #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      # Report error back to coordinator
      Ai::StreamingToolCoordinatorV2.tool_completed(
        message_id,
        execution_id,
        tool_index,
        nil,
        e.message
      )
    ensure
      # Always broadcast final update
      broadcast_final_update
    end
  end

  private

  def update_status_with_retry(status, max_retries = 5)
    retry_count = 0

    begin
      # Reload to get latest data
      @message.reload
      flow = @message.conversation_flow.deep_dup

      # Find the tools entry for this execution
      tools_entry = flow.reverse.find { |item|
        item["type"] == "tools" && item["execution_id"] == @execution_id
      }

      if tools_entry && tools_entry["tools"] && tools_entry["tools"][@tool_index]
        tool = tools_entry["tools"][@tool_index]

        # Don't overwrite final states
        current_status = tool["status"]
        if %w[complete error].include?(current_status)
          Rails.logger.info "[V2_TOOL_JOB] Tool already in final state '#{current_status}', skipping update"
          return
        end

        tool["status"] = status
        tool["started_at"] = Time.current.iso8601 if status == "running"

        # Use update_columns to avoid callbacks and locks
        @message.update_columns(
          conversation_flow: flow,
          updated_at: Time.current
        )
        Rails.logger.info "[V2_TOOL_JOB] Updated tool #{@tool_index} status to '#{status}'"
      else
        Rails.logger.warn "[V2_TOOL_JOB] Could not find tool #{@tool_index} in execution #{@execution_id}"
      end

      # Broadcast update immediately
      broadcast_status_update(status)
    rescue ActiveRecord::StaleObjectError => e
      retry_count += 1
      if retry_count < max_retries
        Rails.logger.warn "[V2_TOOL_JOB] Retry #{retry_count}/#{max_retries} after lock conflict"
        sleep 0.1 * retry_count
        retry
      else
        Rails.logger.error "[V2_TOOL_JOB] Failed to update status after #{max_retries} retries"
      end
    rescue => e
      Rails.logger.error "[V2_TOOL_JOB] Failed to update status: #{e.message}"
    end
  end

  def broadcast_status_update(status)
    # Broadcast via Turbo Streams for immediate UI update
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{@app.id}_chat",
      target: "app_chat_message_#{@message.id}",
      partial: "account/app_editors/agent_reply_v5",
      locals: {message: @message.reload, app: @app}
    )

    # Also broadcast via ActionCable for JavaScript handlers
    ActionCable.server.broadcast(
      "chat_progress_#{@message.id}",
      {
        action: "tool_status_update",
        message_id: @message.id,
        execution_id: @execution_id,
        tool_index: @tool_index,
        status: status,
        conversation_flow: @message.reload.conversation_flow,
        timestamp: Time.current.iso8601
      }
    )
  rescue => e
    Rails.logger.error "[V2_TOOL_JOB] Broadcast failed: #{e.message}"
  end

  def broadcast_final_update
    # Ensure final state is broadcast even if other updates failed
    @message.reload

    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{@app.id}_chat",
      target: "app_chat_message_#{@message.id}",
      partial: "account/app_editors/agent_reply_v5",
      locals: {message: @message, app: @app}
    )
  rescue => e
    Rails.logger.error "[V2_TOOL_JOB] Final broadcast failed: #{e.message}"
  end
end
