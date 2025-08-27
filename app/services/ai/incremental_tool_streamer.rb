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
            while (event_end = stream_buffer.index("\n\n"))
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
      case event["type"]
      when "message_start"
        # Stream started
        Rails.logger.info "[INCREMENTAL_STREAMER] Stream started"
        
      when "content_block_start"
        handle_content_block_start(event["content_block"], event["index"])
        
      when "content_block_delta"  
        handle_content_block_delta(event["delta"], event["index"])
        
      when "content_block_stop"
        handle_content_block_stop(event["index"])
        
      when "message_delta"
        # Message-level updates (stop_reason, etc)
        if event["delta"]&.dig("stop_reason")
          @stop_reason = event["delta"]["stop_reason"]
        end
        
      when "message_stop"
        @stop_reason = event["stop_reason"] || @stop_reason || "stop"
        Rails.logger.info "[INCREMENTAL_STREAMER] Stream ended with stop_reason: #{@stop_reason}"
      end
    end
    
    def handle_content_block_start(block, index)
      return unless block
      
      case block["type"]
      when "tool_use"
        # NEW TOOL DETECTED - Dispatch callback immediately!
        tool_info = {
          index: @current_tool_index,
          id: block["id"],
          name: block["name"],
          status: 'pending'
        }
        
        @tool_buffers[block["id"]] = {
          name: block["name"],
          id: block["id"],
          input_json: "",
          index: @current_tool_index
        }
        
        @current_tool_index += 1
        
        Rails.logger.info "[INCREMENTAL_STREAMER] Tool detected: #{tool_info[:name]} (#{tool_info[:id]})"
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
      
      case delta["type"]
      when "input_json_delta"
        # Accumulate tool input JSON
        tool_id = find_tool_id_by_index(index)
        if tool_id && @tool_buffers[tool_id]
          @tool_buffers[tool_id][:input_json] += delta["partial_json"] || ""
        end
        
      when "text_delta"
        # Stream text content
        text = delta["text"] || ""
        @text_buffer += text
        @callbacks[:on_text]&.call(text)
        
      when "thinking_delta"
        # Accumulate thinking content
        if @current_thinking
          @current_thinking[:thinking] += delta["thinking"] || ""
        end
      end
    end
    
    def handle_content_block_stop(index)
      # Check if this is a tool completion
      tool_id = find_tool_id_by_index(index)
      
      if tool_id && @tool_buffers[tool_id]
        tool_data = @tool_buffers[tool_id]
        
        begin
          # Parse the complete tool input
          input_json = JSON.parse(tool_data[:input_json])
          
          # Build complete tool call
          tool_call = {
            id: tool_data[:id],
            type: "function",
            function: {
              name: tool_data[:name],
              arguments: input_json.to_json
            },
            index: tool_data[:index]
          }
          
          # CRITICAL: Dispatch tool NOW via callback!
          Rails.logger.info "[INCREMENTAL_STREAMER] Tool complete: #{tool_data[:name]}, dispatching immediately!"
          @callbacks[:on_tool_complete]&.call(tool_call)
          
          # Clean up buffer
          @tool_buffers.delete(tool_id)
          
        rescue JSON::ParserError => e
          Rails.logger.error "[INCREMENTAL_STREAMER] Failed to parse tool input: #{e.message}"
          @callbacks[:on_tool_error]&.call(tool_id, e.message)
        end
      elsif @current_thinking
        # Thinking block completed
        @thinking_blocks << @current_thinking
        @callbacks[:on_thinking]&.call(@current_thinking)
        @current_thinking = nil
      end
    end
    
    def find_tool_id_by_index(index)
      # SSE events use index to reference content blocks
      # We need to map this back to our tool_id
      @tool_buffers.values.find { |t| t[:index] == index }&.dig(:id)
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