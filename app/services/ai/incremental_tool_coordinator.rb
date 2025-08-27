module Ai
  # Enhanced coordinator supporting incremental tool dispatch during streaming
  # Tools are executed AS they arrive, not after the stream completes
  class IncrementalToolCoordinator < StreamingToolCoordinatorV2
    
    def initialize(message, app, iteration_count = 0)
      super(message, iteration_count)
      @app = app
    end
    
    # Initialize for incremental dispatch (unknown tool count)
    def initialize_incremental_execution
      execution_id = generate_execution_id
      
      # Initialize with unknown tool count
      state = {
        'status' => 'streaming',
        'tool_count' => nil,  # Will be determined incrementally
        'dispatched_count' => 0,
        'completed_count' => 0,
        'started_at' => Time.current.to_f,
        'tools' => {}
      }
      
      # Store in cache with longer TTL for streaming
      cache_key = cache_key(execution_id, 'state')
      Rails.cache.write(cache_key, state, expires_in: 10.minutes)
      
      # Add initial tools section to conversation_flow (empty, will populate incrementally)
      add_incremental_tools_section(execution_id)
      
      Rails.logger.info "[INCREMENTAL_COORDINATOR] Initialized execution #{execution_id} for incremental dispatch"
      
      execution_id
    end
    
    # Dispatch a tool immediately as it arrives from the stream
    def dispatch_tool_incrementally(execution_id, tool_call)
      tool_index = allocate_next_tool_index(execution_id)
      
      Rails.logger.info "[INCREMENTAL_COORDINATOR] Dispatching tool #{tool_index}: #{tool_call[:function][:name]}"
      
      # Add to conversation flow immediately
      add_tool_to_flow_incrementally(execution_id, tool_index, tool_call, 'queued')
      
      # Update state
      state_key = cache_key(execution_id, 'state')
      state = Rails.cache.read(state_key)
      
      if state
        state['dispatched_count'] += 1
        state['tools'][tool_index.to_s] = {
          'name' => tool_call[:function][:name],
          'status' => 'queued',
          'dispatched_at' => Time.current.to_f
        }
        Rails.cache.write(state_key, state, expires_in: 10.minutes)
      end
      
      # Enqueue job IMMEDIATELY
      StreamingToolExecutionJobV2.perform_later(
        @message.id,
        execution_id,
        tool_index,
        tool_call,
        @iteration_count || 0
      )
      
      # Broadcast UI update
      broadcast_tool_update(execution_id, tool_index, 'queued')
      
      tool_index
    end
    
    # Wait for all dispatched tools to complete
    def wait_for_incrementally_dispatched_tools(execution_id, timeout: 180)
      start_time = Time.current
      check_interval = 0.5  # Check more frequently for incremental
      
      Rails.logger.info "[INCREMENTAL_COORDINATOR] Waiting for incrementally dispatched tools in execution #{execution_id}"
      
      loop do
        state = get_execution_state(execution_id)
        
        if state.nil?
          Rails.logger.error "[INCREMENTAL_COORDINATOR] Lost state for execution #{execution_id}"
          break
        end
        
        dispatched = state['dispatched_count'] || 0
        completed = state['completed_count'] || 0
        
        Rails.logger.debug "[INCREMENTAL_COORDINATOR] Status: #{completed}/#{dispatched} tools completed"
        
        # All dispatched tools are done
        if dispatched > 0 && completed >= dispatched
          Rails.logger.info "[INCREMENTAL_COORDINATOR] All #{dispatched} tools completed"
          
          # Finalize the tools section
          finalize_incremental_execution(execution_id, state)
          
          return collect_results(execution_id, dispatched)
        end
        
        # Check timeout
        if Time.current - start_time > timeout
          Rails.logger.warn "[INCREMENTAL_COORDINATOR] Timeout after #{timeout}s, marking incomplete tools as failed"
          handle_incremental_timeout(execution_id, state)
          return collect_results_with_timeout(execution_id, state)
        end
        
        sleep check_interval
      end
      
      # Shouldn't reach here, but return what we have
      collect_partial_results(execution_id)
    end
    
    # Mark execution as complete with final tool count
    def finalize_tool_count(execution_id, final_count)
      state_key = cache_key(execution_id, 'state')
      state = Rails.cache.read(state_key)
      
      if state
        state['tool_count'] = final_count
        state['status'] = 'waiting_completion'
        Rails.cache.write(state_key, state, expires_in: 10.minutes)
        
        Rails.logger.info "[INCREMENTAL_COORDINATOR] Finalized tool count: #{final_count} for execution #{execution_id}"
      end
    end
    
    # Broadcast when tool is first detected in stream (PUBLIC for AppBuilderV5)
    def broadcast_tool_detected(execution_id, tool_info)
      ActionCable.server.broadcast(
        "chat_progress_#{@message.id}",
        {
          action: 'tool_detected',
          message_id: @message.id,
          execution_id: execution_id,
          tool_index: tool_info[:index],
          tool_name: tool_info[:name],
          status: tool_info[:status],
          timestamp: Time.current.iso8601
        }
      )
      
      Rails.logger.info "[INCREMENTAL_COORDINATOR] Broadcasted tool detection: #{tool_info[:name]} at index #{tool_info[:index]}"
    rescue => e
      Rails.logger.error "[INCREMENTAL_COORDINATOR] Tool detected broadcast failed: #{e.message}"
    end
    
    private
    
    # Allocate next available tool index atomically
    def allocate_next_tool_index(execution_id)
      index_key = cache_key(execution_id, 'next_index')
      
      # Atomic increment, returns the new value
      index = Rails.cache.increment(index_key, 1, initial: 0, expires_in: 10.minutes)
      index - 1  # Convert to 0-based index
    end
    
    # Add empty tools section that will be populated incrementally
    def add_incremental_tools_section(execution_id)
      @message.reload
      flow = @message.conversation_flow.deep_dup
      
      tools_entry = {
        'type' => 'tools',
        'status' => 'streaming',  # New status for incremental
        'expanded' => true,
        'execution_id' => execution_id,
        'tools' => [],  # Will be populated incrementally
        'timestamp' => Time.current.iso8601
      }
      
      flow << tools_entry
      
      @message.update_columns(
        conversation_flow: flow,
        updated_at: Time.current
      )
      
      broadcast_update("Tools section initialized for incremental streaming")
    end
    
    # Add tool to flow as it arrives
    def add_tool_to_flow_incrementally(execution_id, tool_index, tool_call, status)
      @message.reload
      flow = @message.conversation_flow.deep_dup
      
      # Find tools section
      tools_entry = flow.reverse.find { |item| 
        item['type'] == 'tools' && item['execution_id'] == execution_id 
      }
      
      return unless tools_entry
      
      # Ensure tools array is large enough
      tools_entry['tools'] ||= []
      while tools_entry['tools'].size <= tool_index
        tools_entry['tools'] << nil
      end
      
      # Add/update tool at index
      parsed_args = begin
        JSON.parse(tool_call[:function][:arguments])
      rescue JSON::ParserError
        {}
      end
      
      tools_entry['tools'][tool_index] = {
        'name' => tool_call[:function][:name],
        'arguments' => parsed_args,
        'status' => status,
        'index' => tool_index,
        'added_at' => Time.current.iso8601
      }
      
      @message.update_columns(
        conversation_flow: flow,
        updated_at: Time.current
      )
      
      broadcast_update("Tool added to flow incrementally")
    end
    
    # Finalize execution when all tools complete
    def finalize_incremental_execution(execution_id, state)
      @message.reload
      flow = @message.conversation_flow.deep_dup
      
      tools_entry = flow.reverse.find { |item| 
        item['type'] == 'tools' && item['execution_id'] == execution_id 
      }
      
      if tools_entry
        tools_entry['status'] = 'complete'
        tools_entry['expanded'] = false
        tools_entry['final_count'] = state['dispatched_count']
        tools_entry['completed_at'] = Time.current.iso8601
        
        @message.update_columns(
          conversation_flow: flow,
          updated_at: Time.current
        )
      end
      
      # Check for deployment trigger
      if all_tools_successful_incremental?(execution_id, state)
        trigger_deployment_if_needed
      end
      
      # Cleanup
      cleanup_cache(execution_id)
    end
    
    # Check if all incrementally dispatched tools succeeded
    def all_tools_successful_incremental?(execution_id, state)
      return false unless state
      
      dispatched = state['dispatched_count'] || 0
      return false if dispatched == 0
      
      # Check each tool's result
      (0...dispatched).all? do |i|
        result = Rails.cache.read(cache_key(execution_id, "tool_#{i}_result"))
        result && result['status'] == 'success' && result['error'].nil?
      end
    end
    
    # Handle timeout for incremental execution
    def handle_incremental_timeout(execution_id, state)
      dispatched = state['dispatched_count'] || 0
      completed = state['completed_count'] || 0
      
      # Mark incomplete tools as failed
      (0...dispatched).each do |i|
        result = Rails.cache.read(cache_key(execution_id, "tool_#{i}_result"))
        unless result
          # Mark as timeout
          Rails.cache.write(
            cache_key(execution_id, "tool_#{i}_result"),
            {
              'status' => 'error',
              'error' => 'Tool execution timeout',
              'result' => nil
            },
            expires_in: 5.minutes
          )
        end
      end
      
      # Update flow to show timeout
      @message.reload
      flow = @message.conversation_flow.deep_dup
      
      tools_entry = flow.reverse.find { |item| 
        item['type'] == 'tools' && item['execution_id'] == execution_id 
      }
      
      if tools_entry
        tools_entry['status'] = 'timeout'
        tools_entry['expanded'] = false
        tools_entry['tools'].each_with_index do |tool, i|
          next unless tool
          if tool['status'] != 'complete'
            tool['status'] = 'timeout'
            tool['error'] = 'Execution timeout'
          end
        end
        
        @message.update_columns(
          conversation_flow: flow,
          updated_at: Time.current
        )
      end
    end
    
    # Broadcast tool-specific update
    def broadcast_tool_update(execution_id, tool_index, status)
      ActionCable.server.broadcast(
        "chat_progress_#{@message.id}",
        {
          action: 'incremental_tool_update',
          message_id: @message.id,
          execution_id: execution_id,
          tool_index: tool_index,
          status: status,
          timestamp: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.error "[INCREMENTAL_COORDINATOR] Broadcast failed: #{e.message}"
    end
    
    # Get current execution state
    def get_execution_state(execution_id)
      Rails.cache.read(cache_key(execution_id, 'state'))
    end
    
    # Public method for async job to collect results
    def collect_results_for_execution(execution_id)
      state = get_execution_state(execution_id)
      return [] unless state
      
      dispatched = state['dispatched_count'] || 0
      collect_results(execution_id, dispatched)
    end
    
    # Check if tools are still running (non-blocking)
    def tools_still_running?(execution_id)
      state = get_execution_state(execution_id)
      return false unless state
      
      dispatched = state['dispatched_count'] || 0
      completed = state['completed_count'] || 0
      
      dispatched > 0 && completed < dispatched
    end
    
    # Dispatch tools and return immediately (truly async)
    def dispatch_and_return(execution_id, tool_calls)
      Rails.logger.info "[INCREMENTAL_COORDINATOR] Async dispatch of #{tool_calls.size} tools"
      
      # Dispatch all tools
      tool_calls.each do |tool_call|
        dispatch_tool_incrementally(execution_id, tool_call)
      end
      
      # Return execution info immediately
      {
        execution_id: execution_id,
        tool_count: tool_calls.size,
        status: 'dispatched'
      }
    end
    
    # Collect results for completed tools
    def collect_results(execution_id, tool_count)
      results = []
      
      (0...tool_count).each do |i|
        result = Rails.cache.read(cache_key(execution_id, "tool_#{i}_result"))
        results << (result || { 'status' => 'pending', 'error' => 'No result available' })
      end
      
      results
    end
    
    # Collect partial results when execution incomplete
    def collect_partial_results(execution_id)
      state = get_execution_state(execution_id)
      return [] unless state
      
      dispatched = state['dispatched_count'] || 0
      collect_results(execution_id, dispatched)
    end
    
    # Collect results with timeout handling
    def collect_results_with_timeout(execution_id, state)
      dispatched = state['dispatched_count'] || 0
      results = []
      
      (0...dispatched).each do |i|
        result = Rails.cache.read(cache_key(execution_id, "tool_#{i}_result"))
        if result
          results << result
        else
          results << {
            'status' => 'error',
            'error' => 'Tool execution timeout',
            'result' => nil
          }
        end
      end
      
      results
    end
  end
end