# Simple Tool Streamer for AppBuilderV5 Integration
# Works with existing agent_reply_v5 partial and conversation_flow structure
module Ai
  class SimpleToolStreamer
    def initialize(message, app)
      @message = message
      @app = app
      @tools_started = false
      @last_broadcast_time = Time.current
      @broadcast_interval = 0.5.seconds  # Stream updates every 500ms for real-time feel
      @pending_changes = false
    end

    # Initialize tools section in conversation_flow
    def start_tools_execution(tool_calls)
      return unless @message && tool_calls.present?
      
      Rails.logger.info "[SIMPLE_STREAMER] Starting tools execution: #{tool_calls.size} tools"
      
      # Initialize tool_calls array if not already present
      @message.tool_calls = [] if @message.tool_calls.blank?
      
      # Add tools section to conversation_flow
      tools_entry = {
        type: "tools",
        status: "executing", 
        started_at: Time.current.iso8601,
        tools: tool_calls.map.with_index do |tool_call, index|
          {
            id: index + 1,
            name: tool_call['name'] || tool_call.dig('function', 'name'),
            args: extract_ui_essential_args(tool_call['arguments'] || tool_call.dig('function', 'arguments')),
            status: "pending",
            started_at: nil,
            completed_at: nil,
            error: nil
          }
        end
      }
      
      # Append to conversation_flow and save both fields
      flow = @message.conversation_flow || []
      flow << tools_entry
      @message.update!(conversation_flow: flow, tool_calls: @message.tool_calls)
      @tools_started = true
      
      broadcast_update("Tools execution started")
    end

    # Update individual tool status with buffered broadcasting
    def update_tool_status(tool_name, status, error_msg = nil)
      return unless @tools_started && @message.conversation_flow.present?
      
      Rails.logger.info "[SIMPLE_STREAMER] Updating #{tool_name}: #{status}"
      
      # CRITICAL FIX: Only append to tool_calls for tracking purposes, not for each status update
      # This array is for debugging/audit trail only
      if status == 'complete' || status == 'error'
        @message.tool_calls << {
          'name' => tool_name,
          'status' => status,
          'error' => error_msg,
          'timestamp' => Time.current.iso8601
        }
      end
      
      # Find and update the tools entry in conversation_flow
      flow = @message.conversation_flow.deep_dup
      tools_entry = flow.reverse.find { |item| item['type'] == 'tools' }
      
      if tools_entry
        # CRITICAL FIX: Find the right tool by matching status
        # When updating to 'running', find the first 'pending' tool with this name
        # When updating to 'complete', find the first 'running' tool with this name
        tool = if status == 'running'
          tools_entry['tools']&.find { |t| t['name'] == tool_name && t['status'] == 'pending' }
        elsif status == 'complete' || status == 'error'
          tools_entry['tools']&.find { |t| t['name'] == tool_name && t['status'] == 'running' }
        else
          tools_entry['tools']&.find { |t| t['name'] == tool_name }
        end
        
        if tool
          tool['status'] = status
          tool['started_at'] = Time.current.iso8601 if status == 'running'
          tool['completed_at'] = Time.current.iso8601 if %w[complete error].include?(status)
          tool['error'] = error_msg if error_msg
          
          # Update overall tools status
          all_tools = tools_entry['tools'] || []
          if all_tools.all? { |t| %w[complete error].include?(t['status']) }
            tools_entry['status'] = 'completed'
            tools_entry['completed_at'] = Time.current.iso8601
          end
          
          # Always persist to database immediately (both tool_calls and conversation_flow)
          @message.update!(conversation_flow: flow, tool_calls: @message.tool_calls)
          
          # ALWAYS broadcast immediately for real-time updates
          # This ensures the UI shows the correct state as soon as it changes
          broadcast_update("Tool #{tool_name} #{status}")
          @last_broadcast_time = Time.current
          @pending_changes = false
        else
          Rails.logger.warn "[SIMPLE_STREAMER] Could not find tool #{tool_name} with appropriate status to update to #{status}"
        end
      end
    end

    # Add progress message for current tool (immediate broadcast)
    def add_progress_message(tool_name, message)
      Rails.logger.info "[SIMPLE_STREAMER] Progress for #{tool_name}: #{message}"
      
      # Update tool with progress message
      flow = @message.conversation_flow.deep_dup
      tools_entry = flow.reverse.find { |item| item['type'] == 'tools' }
      
      if tools_entry
        tool = tools_entry['tools']&.find { |t| t['name'] == tool_name }
        if tool
          tool['progress'] = message
          tool['progress_updated_at'] = Time.current.iso8601
          @message.update!(conversation_flow: flow)
          
          # ALWAYS broadcast immediately for real-time progress
          broadcast_update("#{tool_name}: #{message}")
          @last_broadcast_time = Time.current
          @pending_changes = false
        end
      end
    end

    # Complete tools execution and force final broadcast
    def complete_tools_execution
      return unless @tools_started && @message.conversation_flow.present?
      
      Rails.logger.info "[SIMPLE_STREAMER] Completing tools execution"
      
      flow = @message.conversation_flow.deep_dup  
      tools_entry = flow.reverse.find { |item| item['type'] == 'tools' }
      
      if tools_entry && tools_entry['status'] != 'completed'
        tools_entry['status'] = 'completed'
        tools_entry['completed_at'] = Time.current.iso8601
        @message.update!(conversation_flow: flow)
      end
      
      # Always broadcast completion regardless of timing
      broadcast_update("All tools completed")
      @pending_changes = false
    end
    
    # Force broadcast of any pending changes
    def flush_pending_updates
      if @pending_changes
        Rails.logger.info "[SIMPLE_STREAMER] Flushing pending updates"
        broadcast_update("Updating progress...")
        @pending_changes = false
        @last_broadcast_time = Time.current
      end
    end

    private

    # Extract only UI-essential arguments to prevent conversation_flow bloat
    # Instead of storing massive file contents, keep only display-relevant metadata
    def extract_ui_essential_args(args)
      return {} unless args.is_a?(Hash)
      
      essential_args = {}
      
      # Always include file path for UI display
      essential_args['file_path'] = args['file_path'] if args['file_path']
      essential_args['path'] = args['path'] if args['path']
      
      # Include small, display-relevant fields
      essential_args['query'] = args['query'] if args['query']
      essential_args['prompt'] = args['prompt'] if args['prompt'] && args['prompt'].length < 200
      essential_args['start_line'] = args['start_line'] if args['start_line']
      essential_args['end_line'] = args['end_line'] if args['end_line']
      
      # For content fields, store only size metadata instead of full content
      if args['content']
        content_size = args['content'].respond_to?(:bytesize) ? args['content'].bytesize : args['content'].to_s.length
        essential_args['content_size'] = content_size
        essential_args['content_preview'] = args['content'].to_s[0..100] + '...' if content_size > 100
      end
      
      if args['new_content']
        content_size = args['new_content'].respond_to?(:bytesize) ? args['new_content'].bytesize : args['new_content'].to_s.length
        essential_args['new_content_size'] = content_size
      end
      
      essential_args
    end

    def broadcast_update(message = nil)
      return unless @message && @app
      
      Rails.logger.info "[SIMPLE_STREAMER] Broadcasting update: #{message}" if message
      
      # Broadcast via Turbo Streams to update the agent_reply_v5 partial  
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "app_chat_message_#{@message.id}",
        partial: "account/app_editors/agent_reply_v5",
        locals: { message: @message, app: @app }
      )
      
      # Also broadcast via custom channel for any additional handlers
      ActionCable.server.broadcast(
        "chat_progress_#{@message.id}",
        {
          action: 'tool_status_update',  # Changed to match JavaScript expectations
          message_id: @message.id,
          conversation_flow: @message.conversation_flow,
          update_message: message,
          timestamp: Time.current.iso8601
        }
      )
    rescue => e
      Rails.logger.error "[SIMPLE_STREAMER] Broadcast failed: #{e.message}"
    end
  end
end