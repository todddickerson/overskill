# Streaming Tool Executor for Real-Time Updates
# Updates conversation_flow and broadcasts via ActionCable
class Ai::StreamingToolExecutor
  attr_reader :message, :app, :iteration_count

  def initialize(message, app, iteration_count = 0)
    @message = message
    @app = app  
    @iteration_count = iteration_count
    @tool_service = Ai::AiToolService.new(app, { logger: Rails.logger })
  end

  def execute_with_streaming(tool_call, tool_index)
    tool_name = tool_call['name'] || tool_call['function']['name']
    tool_args = tool_call['arguments'] || tool_call['function']['arguments']
    
    # Parse arguments if they're a JSON string
    if tool_args.is_a?(String)
      tool_args = JSON.parse(tool_args) rescue {}
    end
    
    Rails.logger.info "[STREAMING] Starting tool execution: #{tool_name} with args: #{tool_args.inspect}"
    
    # Mark tool as running and broadcast
    update_tool_status(tool_name, tool_args['file_path'], 'running')
    broadcast_update
    
    begin
      # Execute based on tool type with streaming updates
      result = case tool_name
      when 'os-write', 'write'
        execute_write_with_streaming(tool_args)
      when 'os-line-replace', 'line-replace'
        execute_line_replace_with_streaming(tool_args)
      when 'os-delete', 'delete'
        execute_delete_with_streaming(tool_args)
      when 'os-search', 'search'
        execute_search_with_streaming(tool_args)
      when 'generate-new-app-logo', 'generate-image'
        execute_image_with_streaming(tool_args)
      when 'os-view', 'view', 'os-view-code'
        execute_view_with_streaming(tool_args)
      else
        execute_generic_tool(tool_call)
      end
      
      # Mark as complete and broadcast
      update_tool_status(tool_name, tool_args['file_path'], 'complete')
      broadcast_update
      
      # Ensure we return a proper result structure
      if result.nil?
        { success: true, content: "Tool #{tool_name} completed" }
      elsif result.is_a?(Hash) && result[:error]
        result # Already has error structure
      else
        result # Return as-is if properly structured
      end
      
    rescue => e
      Rails.logger.error "[STREAMING] Tool execution failed: #{e.message}"
      update_tool_status(tool_name, tool_args['file_path'], 'error', e.message)
      broadcast_update
      { error: "Tool execution failed: #{e.message}" }
    end
  end

  private

  def execute_write_with_streaming(args)
    file_path = args['file_path']
    content = args['content']
    
    Rails.logger.info "[STREAMING] Writing file: #{file_path}"
    
    # Phase 1: Validate path
    broadcast_tool_progress("Validating file path...")
    sleep(0.1) # Small delay for visual feedback
    
    # Phase 2: Create/update file
    broadcast_tool_progress("Writing content (#{content.bytesize} bytes)...")
    result = @tool_service.write_file(file_path, content)
    
    # Phase 3: Update preview if available
    if @app.preview_url.present?
      broadcast_tool_progress("Updating preview environment...")
      update_preview_file(file_path, content)
    end
    
    result
  end

  def execute_line_replace_with_streaming(args)
    file_path = args['file_path']
    start_line = args['start_line'] 
    end_line = args['end_line']
    new_content = args['new_content']
    
    Rails.logger.info "[STREAMING] Replacing lines #{start_line}-#{end_line} in #{file_path}"
    
    # Phase 1: Read existing file
    broadcast_tool_progress("Reading existing file...")
    
    # Phase 2: Apply changes
    broadcast_tool_progress("Applying line replacements...")
    result = @tool_service.replace_file_content(args)
    
    # Phase 3: Update preview
    if @app.preview_url.present?
      broadcast_tool_progress("Syncing changes to preview...")
      sync_file_to_preview(file_path)
    end
    
    result
  end

  def execute_delete_with_streaming(args)
    file_path = args['file_path']
    
    Rails.logger.info "[STREAMING] Deleting file: #{file_path}"
    
    broadcast_tool_progress("Removing file...")
    result = @tool_service.delete_file(file_path)
    
    if @app.preview_url.present?
      broadcast_tool_progress("Updating preview...")
      remove_file_from_preview(file_path)
    end
    
    result
  end

  def execute_search_with_streaming(args)
    query = args['query']
    path = args['path'] || '.'
    
    Rails.logger.info "[STREAMING] Searching for: #{query}"
    
    broadcast_tool_progress("Searching files...")
    result = @tool_service.search_files(args)
    
    broadcast_tool_progress("Found #{result[:results]&.count || 0} matches")
    
    result
  end

  def execute_image_with_streaming(args)
    prompt = args['prompt']
    
    Rails.logger.info "[STREAMING] Generating image: #{prompt}"
    
    broadcast_tool_progress("Generating logo with AI...")
    sleep(0.5) # Image generation takes time
    
    # Delegate to tool service's logo generation
    result = @tool_service.generate_app_logo(args)
    
    broadcast_tool_progress("Logo generated successfully")
    
    result
  end

  def execute_view_with_streaming(args)
    file_path = args['file_path']
    
    Rails.logger.info "[STREAMING] Viewing file: #{file_path}"
    
    broadcast_tool_progress("Reading file contents...")
    result = @tool_service.read_file(file_path, args['lines'])
    
    result
  end

  def execute_generic_tool(tool_call)
    tool_name = tool_call['name'] || tool_call['function']['name']
    tool_args = tool_call['arguments'] || tool_call['function']['arguments'] || {}
    
    # Parse arguments if they're a JSON string
    if tool_args.is_a?(String)
      tool_args = JSON.parse(tool_args) rescue {}
    end
    
    Rails.logger.info "[STREAMING] Executing generic tool: #{tool_name} with args: #{tool_args.inspect}"
    
    # Try to find and execute the tool method
    method_name = tool_name.underscore.gsub('-', '_')
    
    if @tool_service.respond_to?(method_name)
      # Pass arguments as hash, not splat - most tool methods expect a hash
      result = @tool_service.send(method_name, tool_args)
      Rails.logger.info "[STREAMING] Generic tool #{tool_name} returned: #{result.inspect}"
      result
    else
      Rails.logger.error "[STREAMING] Unknown tool method: #{method_name}"
      { error: "Unknown tool: #{tool_name}" }
    end
  end

  def update_tool_status(tool_name, file_path, status, error_msg = nil)
    return unless @message.conversation_flow.present?
    
    Rails.logger.info "[STREAMING] Updating tool status: #{tool_name} - #{status}"
    
    # Update status in conversation_flow
    updated_flow = @message.conversation_flow.deep_dup
    
    # Find the most recent tools entry and update the matching tool
    updated_flow.reverse.each do |item|
      next unless item['type'] == 'tools'
      
      # FIXED: Use 'tools' key to match StreamingToolCoordinator structure
      tools = item['tools'] || []
      tools.each do |tool|
        # Match by name (and optionally file_path if present)
        if tool['name'] == tool_name && (file_path.nil? || tool['file_path'] == file_path || tool.dig('args', 'file_path') == file_path)
          tool['status'] = status
          tool['error'] = error_msg if error_msg
          tool['updated_at'] = Time.current.iso8601
          # Set result if completing with error
          if status == 'complete' && error_msg
            tool['result'] = { error: error_msg }
          end
          break
        end
      end
    end
    
    # Save updated flow
    @message.conversation_flow = updated_flow
    @message.save!
  end

  def broadcast_tool_progress(progress_message)
    Rails.logger.info "[STREAMING] Progress: #{progress_message}"
    
    # Could enhance this to update a progress field in the tool
    # For now, just log it - the status updates are the main feedback
  end

  def broadcast_update
    return unless @message && @app
    
    Rails.logger.info "[STREAMING] Broadcasting update for message #{@message.id}"
    
    # Broadcast via Turbo Streams to re-render the agent_reply_v5 partial
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{@app.id}_chat",
      target: "app_chat_message_#{@message.id}",
      partial: "account/app_editors/agent_reply_v5",
      locals: { message: @message, app: @app }
    )
    
    # Also broadcast via ChatProgressChannel for any custom handlers
    ActionCable.server.broadcast(
      "chat_progress_#{@message.id}",
      {
        action: 'tool_status_update',
        message_id: @message.id,
        conversation_flow: @message.conversation_flow,
        timestamp: Time.current.iso8601
      }
    )
  rescue => e
    Rails.logger.error "[STREAMING] Broadcast failed: #{e.message}"
  end

  def update_preview_file(file_path, content)
    # Send file update to preview environment via WebSocket
    return unless @app.preview_url.present?
    
    ActionCable.server.broadcast(
      "preview_#{@app.id}",
      {
        action: 'file_update',
        path: file_path,
        content: content,
        timestamp: Time.current.iso8601
      }
    )
  end

  def sync_file_to_preview(file_path)
    return unless @app.preview_url.present?
    
    app_file = @app.app_files.find_by(path: file_path)
    return unless app_file
    
    ActionCable.server.broadcast(
      "preview_#{@app.id}",
      {
        action: 'file_sync',
        path: file_path,
        content: app_file.content,
        timestamp: Time.current.iso8601
      }
    )
  end

  def remove_file_from_preview(file_path)
    return unless @app.preview_url.present?
    
    ActionCable.server.broadcast(
      "preview_#{@app.id}",
      {
        action: 'file_remove',
        path: file_path,
        timestamp: Time.current.iso8601
      }
    )
  end
end