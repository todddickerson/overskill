# Handles continuation after incremental tools complete asynchronously
class IncrementalToolCompletionJob < ApplicationJob
  queue_as :tools
  
  def perform(message_id, execution_id, conversation_messages, iteration_count = 0)
    @message = AppChatMessage.find(message_id)
    @app = @message.app
    @execution_id = execution_id
    @conversation_messages = conversation_messages
    @iteration_count = iteration_count
    
    Rails.logger.info "[INCREMENTAL_COMPLETION] Starting completion check for execution #{execution_id}"
    
    # Get coordinator to check status
    coordinator = Ai::IncrementalToolCoordinator.new(@message, @app, iteration_count)
    
    # Non-blocking check - just get current state
    state = coordinator.get_execution_state(execution_id)
    
    if state.nil?
      Rails.logger.error "[INCREMENTAL_COMPLETION] No state found for execution #{execution_id}"
      return
    end
    
    dispatched = state['dispatched_count'] || 0
    completed = state['completed_count'] || 0
    
    Rails.logger.info "[INCREMENTAL_COMPLETION] Status: #{completed}/#{dispatched} tools completed"
    
    if dispatched > 0 && completed >= dispatched
      # All tools completed - continue conversation
      handle_tools_completed(coordinator)
    elsif Time.current.to_f - state['started_at'] > 180
      # Timeout - handle gracefully
      handle_timeout(coordinator, state)
    else
      # Still running - reschedule check
      Rails.logger.info "[INCREMENTAL_COMPLETION] Tools still running, rescheduling check"
      IncrementalToolCompletionJob.set(wait: 2.seconds).perform_later(
        message_id, 
        execution_id, 
        conversation_messages,
        iteration_count
      )
    end
  end
  
  private
  
  def handle_tools_completed(coordinator)
    Rails.logger.info "[INCREMENTAL_COMPLETION] All tools completed, continuing conversation"
    
    # Collect results
    tool_results_raw = coordinator.collect_results_for_execution(@execution_id)
    
    # Get the original dispatched tools from conversation flow
    flow = @message.reload.conversation_flow
    tools_entry = flow.reverse.find { |item| 
      item['type'] == 'tools' && item['execution_id'] == @execution_id 
    }
    
    if tools_entry.nil?
      Rails.logger.error "[INCREMENTAL_COMPLETION] Could not find tools entry for execution_id: #{@execution_id}"
      Rails.logger.error "[INCREMENTAL_COMPLETION] Available execution_ids: #{flow.select{|i| i['type'] == 'tools'}.map{|i| i['execution_id']}.inspect}"
      return
    end
    
    # Format tool results for Claude
    tool_results = format_tool_results(tools_entry['tools'], tool_results_raw)
    
    # Add tool results to conversation and continue
    # Tool results should be individual content items in the user message
    user_message = {
      role: 'user',
      content: tool_results  # This is already an array of properly formatted tool_result objects
    }
    
    updated_messages = @conversation_messages + [user_message]
    
    # Continue the conversation with AppBuilderV5
    builder = Ai::AppBuilderV5.new(@message)
    builder.continue_incremental_conversation(updated_messages, @iteration_count)
    
    # Finalize in coordinator
    coordinator.finalize_incremental_execution(@execution_id, coordinator.get_execution_state(@execution_id))
  rescue => e
    Rails.logger.error "[INCREMENTAL_COMPLETION] Error handling completion: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
  
  def handle_timeout(coordinator, state)
    Rails.logger.warn "[INCREMENTAL_COMPLETION] Execution timeout for #{@execution_id}"
    
    # Mark incomplete tools as failed
    coordinator.handle_incremental_timeout(@execution_id, state)
    
    # Update app status
    @app.update(status: 'error')
    
    # Broadcast error to UI
    Turbo::StreamsChannel.broadcast_append_to(
      "app_#{@app.id}_chat",
      target: "app_chat_messages",
      partial: "account/app_editors/error_message",
      locals: { 
        message: "Tool execution timeout. Some operations may not have completed.",
        app: @app 
      }
    )
  end
  
  def format_tool_results(tools, results_raw)
    formatted = []
    
    Rails.logger.info "[INCREMENTAL_COMPLETION] Formatting #{tools.count} tool results"
    
    tools.each_with_index do |tool, index|
      if tool.nil?
        Rails.logger.warn "[INCREMENTAL_COMPLETION] Tool at index #{index} is nil, skipping"
        next
      end
      
      result = results_raw[index]
      tool_id = tool['id']
      
      Rails.logger.info "[INCREMENTAL_COMPLETION] Tool #{index}: name=#{tool['name']}, id=#{tool_id.inspect}"
      
      # Handle nil result (tool might not have completed)
      if result.nil?
        Rails.logger.warn "[INCREMENTAL_COMPLETION] No result found for tool at index #{index}"
        
        # CRITICAL: Only add tool_result if we have a valid tool_use_id
        if tool_id.present?
          formatted << {
            type: 'tool_result',
            tool_use_id: tool_id,
            content: 'Tool execution incomplete'
          }
        else
          Rails.logger.error "[INCREMENTAL_COMPLETION] Cannot create tool_result without tool_use_id for tool at index #{index}"
        end
      else
        # Ensure content is always a string for Claude API
        content = result['result'] || result['error'] || 'No result available'
        content = content.is_a?(String) ? content : content.to_json
        
        # CRITICAL: Only add tool_result if we have a valid tool_use_id
        if tool_id.present?
          formatted << {
            type: 'tool_result',
            tool_use_id: tool_id,
            content: content
          }
        else
          Rails.logger.error "[INCREMENTAL_COMPLETION] Cannot create tool_result without tool_use_id for tool: #{tool['name']}"
        end
      end
    end
    
    Rails.logger.info "[INCREMENTAL_COMPLETION] Formatted #{formatted.count} tool results (some may have been skipped due to missing IDs)"
    formatted
  end
end