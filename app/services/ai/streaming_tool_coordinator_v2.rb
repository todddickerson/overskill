# Improved StreamingToolCoordinator using Rails.cache for better reliability
class Ai::StreamingToolCoordinatorV2
  include ActionView::Helpers::DateHelper

  COMPLETION_TIMEOUT = 180 # seconds
  CACHE_KEY_PREFIX = "streaming_tools"
  CACHE_TTL = 300 # 5 minutes

  def initialize(message, iteration_count = 0)
    @message = message
    @app = message.app
    @iteration_count = iteration_count
  end

  # Main entry point - launches all tools in parallel and waits for completion
  def execute_tools_in_parallel(tool_calls)
    execution_id = generate_execution_id
    total_tools = tool_calls.size

    Rails.logger.info "[V2_COORDINATOR] Starting parallel execution of #{total_tools} tools with ID: #{execution_id}"

    # Initialize execution state in cache
    Rails.logger.info "[V2_COORDINATOR] About to init execution state for #{execution_id}"
    init_execution_state(execution_id, total_tools)

    # Verify state was written
    state_key = cache_key(execution_id, "state")
    state_check = Rails.cache.read(state_key)
    Rails.logger.info "[V2_COORDINATOR] State after init: #{state_check.inspect}"

    # Add tools section to conversation flow
    add_tools_to_conversation_flow(tool_calls, execution_id)

    # Launch all tool jobs in parallel
    launch_all_tools(tool_calls, execution_id)

    # Wait for all tools to complete
    completed_tools = wait_for_all_tools_completion(total_tools, execution_id)

    # Finalize execution
    finalize_execution(execution_id)

    # Clean up cache
    cleanup_cache(execution_id)

    # Generate tool results for Claude
    generate_real_tool_results(tool_calls, completed_tools)
  end

  # Class method for tool jobs to report completion
  def self.tool_completed(message_id, execution_id, tool_index, result = nil, error = nil)
    message = AppChatMessage.find(message_id)
    # Note: We don't need a full coordinator instance, just handle the completion directly
    Rails.logger.info "[V2_COORDINATOR] Static tool_completed called for execution #{execution_id}, tool #{tool_index}"

    # Store completion in cache with the EXACT execution_id passed
    cache_key = "streaming_tools:#{execution_id}:tool_#{tool_index}_completed"
    tool_data = {
      status: error ? "error" : "complete",
      result: result,
      error: error,
      completed_at: Time.current.iso8601
    }.compact

    # Write to cache with TTL
    success = Rails.cache.write(cache_key, tool_data, expires_in: CACHE_TTL)
    Rails.logger.info "[V2_COORDINATOR] Cache write for tool #{tool_index}: #{success ? "SUCCESS" : "FAILED"}"
    Rails.logger.info "[V2_COORDINATOR] Cache key: #{cache_key}"

    # Update database directly
    coordinator = new(message, 0)
    coordinator.send(:update_tool_status_atomically, execution_id, tool_index, error ? "error" : "complete", result, error)
    coordinator.send(:broadcast_tool_update, tool_index, error ? "error" : "complete")

    # Check if all tools completed and trigger deployment if needed
    if coordinator.send(:all_tools_completed?, execution_id)
      Rails.logger.info "[V2_COORDINATOR] All tools completed for execution #{execution_id}"
      coordinator.send(:finalize_execution, execution_id)
    end
  end

  def handle_tool_completion(execution_id, tool_index, result, error)
    Rails.logger.info "[V2_COORDINATOR] Tool #{tool_index} completed: #{error ? "ERROR" : "SUCCESS"}"

    # Store completion in cache with unique key per tool
    completion_key = cache_key(execution_id, "tool_#{tool_index}_completed")
    tool_data = {
      status: error ? "error" : "complete",
      result: result,
      error: error,
      completed_at: Time.current.iso8601
    }.compact

    # Write to cache with TTL
    success = Rails.cache.write(completion_key, tool_data, expires_in: CACHE_TTL)
    Rails.logger.info "[V2_COORDINATOR] Cache write for tool #{tool_index}: #{success ? "SUCCESS" : "FAILED"}"
    Rails.logger.info "[V2_COORDINATOR] Cache key: #{completion_key}"

    # Atomic database update using optimistic locking
    update_tool_status_atomically(execution_id, tool_index, error ? "error" : "complete", result, error)

    # Broadcast update
    broadcast_tool_update(tool_index, error ? "error" : "complete")

    # Check if all tools are complete
    if all_tools_completed?(execution_id)
      Rails.logger.info "[V2_COORDINATOR] All tools completed for execution #{execution_id}"
      finalize_execution(execution_id)
    end
  end

  private

  def generate_execution_id
    "#{@message.id}_#{SecureRandom.hex(8)}"
  end

  def cache_key(execution_id, suffix = nil)
    parts = [CACHE_KEY_PREFIX, execution_id]
    parts << suffix if suffix
    parts.join(":")
  end

  def init_execution_state(execution_id, total_tools)
    state_key = cache_key(execution_id, "state")
    state = {
      tool_count: total_tools,
      started_at: Time.current.iso8601,
      message_id: @message.id
    }
    Rails.cache.write(state_key, state, expires_in: CACHE_TTL)
  end

  def add_tools_to_conversation_flow(tool_calls, execution_id)
    # REMOVED with_lock - was causing deadlocks with multiple workers
    @message.reload
    flow = @message.conversation_flow.deep_dup || []

    tools_entry = {
      "type" => "tools",
      "execution_id" => execution_id,
      "status" => "streaming",
      "expanded" => true,
      "started_at" => Time.current.iso8601,
      "tools" => tool_calls.map.with_index do |tool_call, index|
        tool_name = tool_call["function"]["name"]
        tool_args = begin
          JSON.parse(tool_call["function"]["arguments"])
        rescue
          {}
        end

        {
          "id" => index,
          "name" => tool_name,
          "args" => tool_args,
          "file_path" => tool_args["file_path"],
          "status" => "pending",
          "started_at" => nil,
          "completed_at" => nil,
          "error" => nil,
          "result" => nil
        }
      end
    }

    flow << tools_entry
    # Use update_columns to avoid callbacks and locks
    @message.update_columns(
      conversation_flow: flow,
      updated_at: Time.current
    )

    broadcast_update("Started streaming execution of #{tool_calls.size} tools")
  end

  def launch_all_tools(tool_calls, execution_id)
    tool_calls.each_with_index do |tool_call, tool_index|
      # Update status to queued before launching
      update_tool_status_atomically(execution_id, tool_index, "queued")

      # Launch Sidekiq job (Using V2 job)
      # Attempting to fix race conditions by launching jobs
      StreamingToolExecutionJobV2.set(wait: (tool_index * 0.5).seconds).perform_later(
        @message.id,
        execution_id,
        tool_index,
        tool_call,
        @iteration_count
      )

      Rails.logger.info "[V2_COORDINATOR] Launched job for tool #{tool_index} with wait: #{(tool_index * 0.5).seconds} #{Time.now.strftime("%H:%M:%S")}"
    rescue => e
      Rails.logger.error "[V2_COORDINATOR] Failed to launch job for tool #{tool_index}: #{e.message}"
      handle_tool_completion(execution_id, tool_index, nil, "Failed to launch: #{e.message}")
    end
  end

  def wait_for_all_tools_completion(total_tools, execution_id)
    Rails.logger.info "[V2_COORDINATOR] Waiting for #{total_tools} tools to complete"

    start_time = Time.current
    completed_tools = {}
    check_count = 0

    loop do
      check_count += 1

      # Check timeout
      if Time.current - start_time > COMPLETION_TIMEOUT
        Rails.logger.error "[V2_COORDINATOR] Timeout waiting for tools after #{COMPLETION_TIMEOUT}s"
        break
      end

      # Log every 10th check (every 5 seconds)
      if check_count % 10 == 0
        Rails.logger.info "[V2_COORDINATOR] Still waiting... Check ##{check_count}, completed: #{completed_tools.size}/#{total_tools}"
      end

      # Check each tool's completion status in cache AND database
      (0...total_tools).each do |tool_index|
        next if completed_tools.key?(tool_index)

        # First check cache
        completion_key = cache_key(execution_id, "tool_#{tool_index}_completed")
        tool_data = Rails.cache.read(completion_key)

        if tool_data
          # Handle both symbol and string keys for compatibility
          tool_data = tool_data.with_indifferent_access if tool_data.is_a?(Hash)
          completed_tools[tool_index] = tool_data
          Rails.logger.info "[V2_COORDINATOR] Tool #{tool_index} completed (from cache): #{tool_data["status"]}"
        else
          # If not in cache, check database as fallback
          @message.reload
          flow = @message.conversation_flow
          if flow
            tools_entry = flow.find { |item|
              item["type"] == "tools" && item["execution_id"] == execution_id
            }
            if tools_entry && tools_entry["tools"] && tools_entry["tools"][tool_index]
              tool = tools_entry["tools"][tool_index]
              if %w[complete error].include?(tool["status"])
                completed_tools[tool_index] = {
                  "status" => tool["status"],
                  "result" => tool["result"],
                  "error" => tool["error"],
                  "completed_at" => tool["completed_at"]
                }.compact
                Rails.logger.info "[V2_COORDINATOR] Tool #{tool_index} completed (from DB): #{tool["status"]}"
              end
            end
          end
        end
      end

      # Check if all tools are complete
      if completed_tools.size >= total_tools
        Rails.logger.info "[V2_COORDINATOR] All #{total_tools} tools completed"
        break
      end

      sleep 0.5
    end

    # Handle any tools that didn't complete
    (0...total_tools).each do |tool_index|
      unless completed_tools.key?(tool_index)
        Rails.logger.warn "[V2_COORDINATOR] Tool #{tool_index} timed out"
        handle_tool_completion(execution_id, tool_index, nil, "Tool execution timed out")
        completed_tools[tool_index] = {"status" => "error", "error" => "Timeout"}
      end
    end

    completed_tools
  end

  def update_tool_status_atomically(execution_id, tool_index, status, result = nil, error = nil)
    max_retries = 10  # Increased retries for high concurrency
    retry_count = 0

    begin
      # REMOVED with_lock - was causing deadlocks with multiple workers
      @message.reload
      flow = @message.conversation_flow.deep_dup

      # Find the tools entry for this execution
      tools_entry = flow.reverse.find { |item|
        item["type"] == "tools" && item["execution_id"] == execution_id
      }

      if tools_entry && tools_entry["tools"] && tools_entry["tools"][tool_index]
        tool = tools_entry["tools"][tool_index]

        # Don't overwrite final states with intermediate states
        current_status = tool["status"]
        if %w[complete error].include?(current_status) && %w[queued running].include?(status)
          Rails.logger.info "[V2_COORDINATOR] Tool #{tool_index} already in final state '#{current_status}', skipping update to '#{status}'"
          return
        end

        # Update tool data
        tool["status"] = status
        tool["started_at"] ||= Time.current.iso8601 if status == "running"
        tool["completed_at"] = Time.current.iso8601 if %w[complete error].include?(status)
        tool["error"] = error if error
        tool["result"] = result if result && status == "complete"

        # Use update_columns to avoid callbacks and locks
        @message.update_columns(
          conversation_flow: flow,
          updated_at: Time.current
        )
        Rails.logger.info "[V2_COORDINATOR] Updated tool #{tool_index} to status '#{status}'"
      else
        Rails.logger.warn "[V2_COORDINATOR] Could not find tool #{tool_index} in execution #{execution_id}"
      end
    rescue ActiveRecord::StaleObjectError, ActiveRecord::RecordNotUnique => e
      retry_count += 1
      if retry_count < max_retries
        Rails.logger.warn "[V2_COORDINATOR] Database conflict (#{e.class.name}), retry #{retry_count}/#{max_retries}"
        sleep (0.1 * (2**retry_count)).clamp(0, 2)  # Exponential backoff, max 2 seconds
        @message.reload  # Reload before retry
        retry
      else
        Rails.logger.error "[V2_COORDINATOR] Failed to update after #{max_retries} retries: #{e.message}"
      end
    end
  end

  def all_tools_completed?(execution_id)
    state_key = cache_key(execution_id, "state")
    state = Rails.cache.read(state_key) # TODO: Fix this, returning nil
    return false unless state

    total_tools = state["tool_count"]
    completed_count = 0

    (0...total_tools).each do |tool_index|
      completion_key = cache_key(execution_id, "tool_#{tool_index}_completed")
      completed_count += 1 if Rails.cache.exist?(completion_key)
    end

    completed_count >= total_tools
  end

  def all_tools_successful?(execution_id)
    state_key = cache_key(execution_id, "state")
    Rails.logger.info "[V2_COORDINATOR] Checking success for #{execution_id}, state_key: #{state_key}"
    state = Rails.cache.read(state_key)

    if state.nil?
      Rails.logger.error "[V2_COORDINATOR] State is nil for execution #{execution_id}! Cache key: #{state_key}"
      # Fall back to checking database
      Rails.logger.info "[V2_COORDINATOR] Attempting database fallback for success check"
      @message.reload
      flow = @message.conversation_flow || []
      tools_entry = flow.reverse.find { |item|
        item["type"] == "tools" && item["execution_id"] == execution_id
      }

      if tools_entry && tools_entry["tools"]
        total_tools = tools_entry["tools"].size
        successful_count = tools_entry["tools"].count { |tool| tool["status"] == "complete" }
        Rails.logger.info "[V2_COORDINATOR] Database fallback - Tool success check: #{successful_count}/#{total_tools} successful"
        return successful_count == total_tools
      else
        Rails.logger.error "[V2_COORDINATOR] Could not find tools entry in database for execution #{execution_id}"
        return false
      end
    end

    total_tools = state["tool_count"]
    successful_count = 0

    (0...total_tools).each do |tool_index|
      completion_key = cache_key(execution_id, "tool_#{tool_index}_completed")
      tool_data = Rails.cache.read(completion_key)
      # Handle both symbol and string keys for compatibility
      tool_data = tool_data.with_indifferent_access if tool_data.is_a?(Hash)
      if tool_data && tool_data["status"] == "complete"
        successful_count += 1
        Rails.logger.debug "[V2_COORDINATOR] Tool #{tool_index}: complete"
      else
        Rails.logger.debug "[V2_COORDINATOR] Tool #{tool_index}: not complete - data: #{tool_data.inspect}"
      end
    end

    Rails.logger.info "[V2_COORDINATOR] Tool success check: #{successful_count}/#{total_tools} successful execution_id: #{execution_id}"
    successful_count == total_tools
  end

  def finalize_execution(execution_id)
    Rails.logger.info "[V2_COORDINATOR] Finalizing execution #{execution_id}"

    # REMOVED with_lock - was causing deadlocks with multiple workers
    @message.reload
    flow = @message.conversation_flow.deep_dup
    tools_entry = flow.reverse.find { |item|
      item["type"] == "tools" && item["execution_id"] == execution_id
    }

    if tools_entry
      tools_entry["status"] = "completed"
      tools_entry["expanded"] = false
      tools_entry["completed_at"] = Time.current.iso8601
      # Use update_columns to avoid callbacks and locks
      @message.update_columns(
        conversation_flow: flow,
        updated_at: Time.current
      )
    end

    broadcast_update("All tools completed")

    # CRITICAL FIX: Trigger deployment if all tools completed successfully
    Rails.logger.info "[V2_COORDINATOR] Checking if all tools successful for deployment trigger..."
    success_check = all_tools_successful?(execution_id)
    Rails.logger.info "[V2_COORDINATOR] Tool success check result: #{success_check}"

    if success_check
      Rails.logger.info "[V2_COORDINATOR] All tools successful, triggering deployment for app #{@app.id}"
      job = DeployAppJob.perform_later(@app.id)
      Rails.logger.info "[V2_COORDINATOR] Triggered DeployAppJob with job ID: #{job&.job_id} for app #{@app.id}"
    else
      Rails.logger.warn "[V2_COORDINATOR] Not all tools successful, skipping deployment"
    end
  end

  def cleanup_cache(execution_id)
    state_key = cache_key(execution_id, "state")

    # Read state BEFORE deleting it
    state = Rails.cache.read(state_key)

    # Now delete the state
    Rails.cache.delete(state_key)

    # Clean up individual tool completions
    if state && state["tool_count"]
      (0...state["tool_count"]).each do |tool_index|
        completion_key = cache_key(execution_id, "tool_#{tool_index}_completed")
        Rails.cache.delete(completion_key)
      end
    end
  end

  def broadcast_update(message)
    Rails.logger.info "[V2_COORDINATOR] Broadcasting: #{message}"

    # Broadcast to Turbo Stream
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{@app.id}_chat",
      target: "app_chat_message_#{@message.id}",
      partial: "account/app_editors/agent_reply_v5",
      locals: {message: @message, app: @app}
    )
  end

  def broadcast_tool_update(tool_index, status)
    # Broadcast specific tool update via ActionCable
    ActionCable.server.broadcast(
      "chat_progress_#{@message.id}",
      {
        action: "tool_status_update",
        message_id: @message.id,
        tool_index: tool_index,
        status: status,
        conversation_flow: @message.reload.conversation_flow,
        timestamp: Time.current.iso8601
      }
    )
  end

  def generate_real_tool_results(tool_calls, completed_tools)
    tool_results = []

    tool_calls.each_with_index do |tool_call, index|
      tool_name = tool_call["function"]["name"]
      tool_id = tool_call["id"]
      completion_data = completed_tools[index] || {}

      tool_result_block = {
        type: "tool_result",
        tool_use_id: tool_id
      }

      case completion_data["status"]
      when "complete"
        # CRITICAL FIX: Proper nil safety for result access
        result = completion_data["result"]
        tool_result_block[:content] = if result.is_a?(Hash) && result[:content]
          result[:content]
        elsif result.is_a?(Hash) && result["content"]
          result["content"]
        else
          "Tool #{tool_name} completed successfully"
        end
        Rails.logger.debug "[V2_COORDINATOR_FIX] Tool #{index} result processed: #{result.class}, has_content: #{result.is_a?(Hash) && (result[:content] || result["content"])}"
      when "error"
        tool_result_block[:content] = completion_data["error"] || "Tool execution failed"
      else
        tool_result_block[:content] = "Tool #{tool_name} status unknown"
      end

      tool_results << tool_result_block
    end

    Rails.logger.info "[V2_COORDINATOR] Generated #{tool_results.size} tool results"
    tool_results
  end
end
