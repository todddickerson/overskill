require 'net/http'
require 'json'

module Ai
  # Handles incremental streaming of Claude responses with immediate tool dispatch
  # This enables tools to start executing WHILE Claude is still streaming, not after
  class IncrementalToolStreamer
    
    attr_reader :callbacks, :tool_buffers, :current_tool_index, :text_buffer
    
    def initialize(anthropic_client)
      @client = anthropic_client
      @tool_buffers = {}
      @current_tool_index = 0
      @text_buffer = ""
      @thinking_blocks = []
    end
    
    # Stream chat with tools, dispatching them incrementally as they arrive
    # 
    # @param messages [Array] Conversation messages
    # @param tools [Array] Available tools  
    # @param callbacks [Hash] Event callbacks:
    #   - on_tool_start: ->(tool_info) { ... } Called when tool detected
    #   - on_tool_complete: ->(tool_call) { ... } Called when tool JSON complete
    #   - on_text: ->(text) { ... } Called for text content chunks
    #   - on_thinking: ->(block) { ... } Called for thinking blocks
    #   - on_complete: ->(result) { ... } Called when stream ends
    #
    def stream_chat_with_tools(messages, tools, callbacks = {}, options = {})
      @callbacks = callbacks
      # Resolve model symbol to ID (same as AnthropicClient)
      model = options[:model] || :claude_sonnet_4
      model_id = @client.class::MODELS[model] || model || 'claude-sonnet-4-20250514'
      
      # Build request body
      body = build_request_body(messages, tools, model_id, options)
      
      # Setup HTTP streaming connection
      uri = URI("#{@client.class.base_uri}/v1/messages")
      Rails.logger.info "[INCREMENTAL_STREAMER] Starting stream to #{uri}"
      
      # Use Net::HTTP for true streaming
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 500) do |http|
        request = build_request(uri, body)
        
        # Stream the response
        http.request(request) do |response|
          unless response.code == '200'
            handle_error_response(response)
            return
          end
          
          stream_buffer = ""
          
          response.read_body do |chunk|
            stream_buffer += chunk
            
            # Process complete SSE events
            event_count = 0
            while (event_end = stream_buffer.index("\n\n"))
              event_count += 1
              
              # Only log debug every 20 events to reduce noise
              if event_count % 20 == 0
                Rails.logger.debug "[INCREMENTAL_STREAMER] Processing SSE event ##{event_count}, event_end: #{event_end.inspect}"
              end
              
              # Safety check for nil event_end (should never happen due to while condition)
              if event_end.nil?
                Rails.logger.error "[INCREMENTAL_STREAMER] event_end is nil, breaking loop"
                break
              end
              
              event_data = stream_buffer[0...event_end]
              stream_buffer = stream_buffer[event_end + 2..-1]
              
              process_sse_event(event_data)
            end
          end
        end
      end
      
      # Final callback with accumulated results
      finalize_stream
      
    rescue => e
      Rails.logger.error "[INCREMENTAL_STREAMER] Stream error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      # Pass error as hash to match expected format
      callbacks[:on_error]&.call({ message: e.message, error: e })
    end
    
    private
    
    def build_request_body(messages, tools, model_id, options)
      # Handle system messages
      system_message = nil
      api_messages = []
      
      messages.each do |msg|
        if msg[:role] == "system"
          if msg[:cache_control]
            api_messages << msg
          else
            system_message = msg[:content]
          end
        else
          api_messages << msg
        end
      end
      
      body = {
        model: model_id,
        messages: api_messages,
        tools: format_tools_for_anthropic(tools),
        tool_choice: { type: "auto" },
        temperature: options[:temperature] || 0.7,
        max_tokens: options[:max_tokens] || 48000,
        stream: true  # CRITICAL: Enable streaming
      }
      
      body[:system] = system_message if system_message
      body
    end
    
    def build_request(uri, body)
      request = Net::HTTP::Post.new(uri)
      
      # Build headers (including Helicone if configured)
      headers = @client.send(:build_request_options)[:headers]
      headers.each { |k, v| request[k] = v }
      
      request.body = body.to_json
      request
    end
    
    def process_sse_event(event_data)
      return if event_data.strip.empty?
      
      # Parse SSE format
      lines = event_data.split("\n")
      event_type = nil
      data = nil
      
      lines.each do |line|
        if line.start_with?("event:")
          event_type = line[6..].strip
        elsif line.start_with?("data:")
          data = line[5..].strip
        end
      end
      
      return unless data && data != "[DONE]"
      
      begin
        json_data = JSON.parse(data)
        handle_stream_event(json_data)
      rescue JSON::ParserError => e
        Rails.logger.error "[INCREMENTAL_STREAMER] Failed to parse: #{e.message}"
      end
    end
    
    def handle_stream_event(event)
      # CRITICAL NIL SAFETY: Check event structure
      unless event.is_a?(Hash)
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Event is not a hash: #{event.class}"
        return
      end
      
      event_type = event["type"]
      unless event_type
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Event missing type field: #{event.inspect}"
        return
      end
      
      case event_type
      when "message_start"
        # Stream started
        Rails.logger.info "[INCREMENTAL_STREAMER] Stream started"
        
      when "content_block_start"
        content_block = event["content_block"]
        index = event["index"]
        
        if content_block.nil?
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** content_block is nil in content_block_start"
          return
        end
        
        handle_content_block_start(content_block, index)
        
      when "content_block_delta"  
        delta = event["delta"]
        index = event["index"]
        
        if delta.nil?
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** delta is nil in content_block_delta"
          return
        end
        
        handle_content_block_delta(delta, index)
        
      when "content_block_stop"
        index = event["index"]
        handle_content_block_stop(index)
        
      when "message_delta"
        # Message-level updates (stop_reason, etc)
        delta = event["delta"]
        if delta&.dig("stop_reason")
          @stop_reason = delta["stop_reason"]
        end
        
      when "message_stop"
        @stop_reason = event["stop_reason"] || @stop_reason || "stop"
        Rails.logger.info "[INCREMENTAL_STREAMER] Stream ended with stop_reason: #{@stop_reason}"
      end
    end
    
    def handle_content_block_start(block, index)
      return unless block
      
      # CRITICAL NIL SAFETY: Validate block structure
      unless block.is_a?(Hash)
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Block is not a hash: #{block.class}"
        return
      end
      
      block_type = block["type"]
      unless block_type
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Block missing type field: #{block.inspect}"
        return
      end
      
      Rails.logger.info "[INCREMENTAL_STREAMER] content_block_start: type=#{block_type}, sse_index=#{index}"
      
      case block_type
      when "tool_use"
        # CRITICAL NIL SAFETY: Validate tool fields
        tool_id = block["id"]
        tool_name = block["name"]
        
        unless tool_id && tool_name
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Tool missing id or name: id=#{tool_id.inspect}, name=#{tool_name.inspect}"
          return
        end
        
        # NEW TOOL DETECTED - Dispatch callback immediately!
        tool_info = {
          index: @current_tool_index,
          id: tool_id,
          name: tool_name,
          status: 'pending'
        }
        
        @tool_buffers[tool_id] = {
          name: tool_name,
          id: tool_id,
          input_json: "",
          index: @current_tool_index,
          sse_block_index: index  # CRITICAL: Track the SSE content block index!
        }
        
        @current_tool_index += 1
        
        Rails.logger.info "[INCREMENTAL_STREAMER] Tool detected: #{tool_info[:name]} (#{tool_info[:id]}) at SSE index #{index}"
        @callbacks[:on_tool_start]&.call(tool_info)
        
      when "text"
        # Text block started
        @text_buffer = ""
        
      when "thinking"
        # Thinking block started  
        @current_thinking = { type: "thinking", thinking: "", signature: nil }
      end
    end
    
    def handle_content_block_delta(delta, index)
      return unless delta
      
      # CRITICAL NIL SAFETY: Validate delta structure
      unless delta.is_a?(Hash)
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Delta is not a hash: #{delta.class}"
        return
      end
      
      delta_type = delta["type"]
      unless delta_type
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Delta missing type field: #{delta.inspect}"
        return
      end
      
      case delta_type
      when "input_json_delta"
        # CRITICAL NIL SAFETY: Validate partial_json field
        json_chunk = delta["partial_json"]
        if json_chunk.nil?
          Rails.logger.warn "[INCREMENTAL_STREAMER] *** NIL SAFETY *** partial_json is nil, using empty string"
          json_chunk = ""
        end
        
        # Rails.logger.info "[INCREMENTAL_STREAMER] input_json_delta for SSE index #{index}: #{json_chunk.length} chars"
        
        # CRITICAL NIL SAFETY: Validate tool_buffers before find operation
        unless @tool_buffers.is_a?(Hash)
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** tool_buffers is not a hash: #{@tool_buffers.class}"
          return
        end
        
        # Find tool by SSE block index with nil safety
        tool_entry = nil
        begin
          tool_entry = @tool_buffers.find { |id, data| data&.[](:sse_block_index) == index }
        rescue => e
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Error finding tool buffer: #{e.message}"
          return
        end
        
        if tool_entry
          tool_id, tool_data = tool_entry
          
          # CRITICAL NIL SAFETY: Validate tool buffer structure
          if tool_id && @tool_buffers[tool_id]&.is_a?(Hash) && @tool_buffers[tool_id][:input_json]
            @tool_buffers[tool_id][:input_json] += json_chunk
            tool_name = tool_data&.[](:name) || "unknown"
            # Rails.logger.info "[INCREMENTAL_STREAMER] Accumulated #{@tool_buffers[tool_id][:input_json].length} chars for tool #{tool_name}"
          else
            Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Tool buffer corrupted for #{tool_id}: #{@tool_buffers[tool_id].inspect}"
          end
        else
          Rails.logger.warn "[INCREMENTAL_STREAMER] No tool buffer found for SSE index #{index}"
        end
        
      when "text_delta"
        # CRITICAL NIL SAFETY: Validate text field
        text = delta["text"]
        if text.nil?
          Rails.logger.warn "[INCREMENTAL_STREAMER] *** NIL SAFETY *** text is nil, using empty string"
          text = ""
        end
        
        @text_buffer += text
        @callbacks[:on_text]&.call(text) if @callbacks
        
      when "thinking_delta"
        # CRITICAL NIL SAFETY: Validate thinking field and current_thinking state
        if @current_thinking&.is_a?(Hash)
          thinking_chunk = delta["thinking"]
          if thinking_chunk.nil?
            Rails.logger.warn "[INCREMENTAL_STREAMER] *** NIL SAFETY *** thinking is nil, using empty string"
            thinking_chunk = ""
          end
          @current_thinking[:thinking] += thinking_chunk
        else
          Rails.logger.warn "[INCREMENTAL_STREAMER] *** NIL SAFETY *** current_thinking is invalid: #{@current_thinking.class}"
        end
      end
    end
    
    def handle_content_block_stop(index)
      Rails.logger.info "[INCREMENTAL_STREAMER] content_block_stop for index #{index}"
      
      # CRITICAL NIL SAFETY: Validate tool_buffers exists
      unless @tool_buffers.is_a?(Hash)
        Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** tool_buffers is not a hash: #{@tool_buffers.class}"
        return
      end
      
      Rails.logger.info "[INCREMENTAL_STREAMER] Current tool_buffers: #{@tool_buffers.keys.inspect}"
      
      # Check if this is a tool completion
      tool_id = find_tool_id_by_index(index)
      Rails.logger.info "[INCREMENTAL_STREAMER] Found tool_id: #{tool_id.inspect} for index #{index}"
      
      if tool_id && @tool_buffers[tool_id]
        tool_data = @tool_buffers[tool_id]
        
        # CRITICAL NIL SAFETY: Validate tool_data structure
        unless tool_data.is_a?(Hash)
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Tool data is not a hash: #{tool_data.class} for tool_id: #{tool_id}"
          return
        end
        
        # CRITICAL NIL SAFETY: Validate required tool fields
        tool_name = tool_data[:name]
        tool_input_json = tool_data[:input_json]
        tool_id_field = tool_data[:id]
        tool_index = tool_data[:index]
        
        unless tool_name && tool_input_json && tool_id_field
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Missing tool fields: name=#{tool_name.inspect}, input_json=#{tool_input_json.inspect}, id=#{tool_id_field.inspect}"
          return
        end
        
        Rails.logger.info "[INCREMENTAL_STREAMER] Tool buffer data: name=#{tool_name}, json_length=#{tool_input_json.length}"
        
        begin
          # CRITICAL NIL SAFETY: Validate input_json before parsing
          if tool_input_json.empty?
            Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Tool input JSON is empty"
            input_json = {}
          else
            input_json = JSON.parse(tool_input_json)
          end
          
          Rails.logger.info "[INCREMENTAL_STREAMER] Successfully parsed JSON for tool #{tool_name}"
          
          # CRITICAL NIL SAFETY: Build complete tool call with validation
          tool_call = {
            id: tool_id_field,
            type: "function",
            function: {
              name: tool_name,
              arguments: input_json.to_json
            },
            index: tool_index
          }
          
          # CRITICAL NIL SAFETY: Validate callbacks before calling
          unless @callbacks.is_a?(Hash)
            Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Callbacks is not a hash: #{@callbacks.class}"
            return
          end
          
          # CRITICAL: Dispatch tool NOW via callback!
          Rails.logger.info "[INCREMENTAL_STREAMER] Tool complete: #{tool_name}, dispatching immediately!"
          @callbacks[:on_tool_complete]&.call(tool_call)
          
          # Clean up buffer
          @tool_buffers.delete(tool_id)
          
        rescue JSON::ParserError => e
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Failed to parse tool input: #{e.message}"
          Rails.logger.error "[INCREMENTAL_STREAMER] Raw JSON: #{tool_input_json.inspect}"
          @callbacks[:on_tool_error]&.call(tool_id, e.message) if @callbacks.is_a?(Hash)
        rescue => e
          Rails.logger.error "[INCREMENTAL_STREAMER] *** NIL SAFETY *** Unexpected error in tool processing: #{e.class.name}: #{e.message}"
          Rails.logger.error "[INCREMENTAL_STREAMER] Backtrace: #{e.backtrace.first(3).join('\n')}"
          @callbacks[:on_tool_error]&.call(tool_id, e.message) if @callbacks.is_a?(Hash)
        end
      elsif @current_thinking&.is_a?(Hash)
        # CRITICAL NIL SAFETY: Validate thinking_blocks exists
        @thinking_blocks ||= []
        
        # Thinking block completed
        @thinking_blocks << @current_thinking
        @callbacks[:on_thinking]&.call(@current_thinking) if @callbacks.is_a?(Hash)
        @current_thinking = nil
      end
    end
    
    def find_tool_id_by_index(index)
      # SSE events use index to reference content blocks
      # We need to map this back to our tool_id
      # NOTE: The index from SSE is the global content block index, not our tool index
      Rails.logger.info "[INCREMENTAL_STREAMER] Searching for tool with SSE block index #{index}"
      @tool_buffers.each do |tool_id, data|
        if data
          Rails.logger.info "[INCREMENTAL_STREAMER]   Buffer #{tool_id}: tool_index=#{data[:index]}, sse_block_index=#{data[:sse_block_index]}"
        else
          Rails.logger.warn "[INCREMENTAL_STREAMER]   Buffer #{tool_id}: data is nil"
        end
      end
      
      # We need to track the SSE block index when creating the tool
      @tool_buffers.find { |id, data| data&.[](:sse_block_index) == index }&.first
    end
    
    def finalize_stream
      # Build final result matching expected format
      result = {
        success: true,
        content: @text_buffer,
        tool_calls: [], # Already dispatched incrementally
        thinking_blocks: @thinking_blocks,
        stop_reason: @stop_reason,
        incremental_dispatch: true  # Flag to indicate new behavior
      }
      
      @callbacks[:on_complete]&.call(result)
    end
    
    def handle_error_response(response)
      error_body = response.body rescue ""
      
      # Check if error is HTML (like Cloudflare errors)
      if error_body.include?('<html') || error_body.include?('<!DOCTYPE')
        Rails.logger.error "[INCREMENTAL_STREAMER] Received HTML error response: #{error_body[0..500]}"
        
        # Extract meaningful error from HTML if possible
        error_message = if error_body.include?('Worker exceeded resource limits')
          "The AI service temporarily exceeded resource limits. Please try again in a moment."
        elsif error_body.include?('Cloudflare')
          "Service temporarily unavailable. Please try again."
        else
          "An unexpected error occurred. Please try again."
        end
        
        @callbacks[:on_error]&.call({
          code: response.code,
          message: error_message,
          type: "service_error"
        })
        return
      end
      
      error = begin
        JSON.parse(error_body)
      rescue
        { "error" => { "message" => "HTTP #{response.code}: #{error_body}" } }
      end
      
      Rails.logger.error "[INCREMENTAL_STREAMER] API Error: #{error}"
      
      @callbacks[:on_error]&.call({
        code: response.code,
        message: error.dig("error", "message") || "Unknown error",
        type: error.dig("error", "type") || "api_error"
      })
    end
    
    def format_tools_for_anthropic(tools)
      return [] if tools.blank?
      
      tools.map do |tool|
        {
          name: tool["name"] || tool[:name],
          description: tool["description"] || tool[:description],
          input_schema: tool["parameters"] || tool[:parameters] || {
            type: "object",
            properties: {},
            required: []
          }
        }
      end
    end
  end
end