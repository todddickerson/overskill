# Enhanced Streaming Buffer Service for Real-time AI Generation
# Handles partial responses, buffers until complete, and provides ideal UX
module Ai
  module Services
    class StreamingBufferEnhanced
      include Rails.application.routes.url_helpers
      
      # Buffer states
      BUFFER_STATES = {
        idle: 'idle',
        buffering_content: 'buffering_content',
        buffering_tool_call: 'buffering_tool_call',
        executing_tool: 'executing_tool',
        completed: 'completed'
      }.freeze
      
      # Generation stages for better UX
      GENERATION_STAGES = {
        structure: { name: 'Building Structure', weight: 0.2 },
        components: { name: 'Creating Components', weight: 0.3 },
        styling: { name: 'Adding Styles', weight: 0.2 },
        interactivity: { name: 'Adding Interactivity', weight: 0.2 },
        polish: { name: 'Polishing & Optimizing', weight: 0.1 }
      }.freeze
      
      attr_reader :state, :current_stage, :progress, :files_created, :broadcaster
      
      def initialize(app, chat_message, broadcaster)
        @app = app
        @chat_message = chat_message
        @broadcaster = broadcaster
        
        @state = BUFFER_STATES[:idle]
        @current_stage = :structure
        @progress = 0.0
        @files_created = []
        
        # Buffers for partial content
        @content_buffer = ""
        @tool_call_buffer = ""
        @current_tool_call = nil
        @tool_calls_queue = []
        
        # Tracking for UX
        @current_file = nil
        @lines_written = 0
        @total_estimated_lines = 500  # Estimate for a typical app
        @stage_progress = {}
        
        # Performance tracking
        @start_time = Time.current
        @last_update_time = Time.current
        @tokens_received = 0
      end
      
      # Start a new generation session
      def start_generation
        @state = BUFFER_STATES[:idle]
        @current_stage = :structure
        @progress = 0.0
        @files_created = []
        @content_buffer = ""
        @tool_call_buffer = ""
        @current_tool_call = nil
        @tool_calls_queue = []
        @start_time = Time.current
        
        Rails.logger.info "[StreamingBuffer] Starting new generation session"
        @broadcaster.update("Initializing AI generation...", 0.05)
      end
      
      # Process incoming chunk from streaming API (called by orchestrator)
      def process_chunk(chunk, &block)
        @tokens_received += 1
        
        # Update progress less frequently
        if Time.current - @last_update_time > 0.5
          update_progress_display
          @last_update_time = Time.current
        end
        
        # Parse SSE data if needed
        data = if chunk.is_a?(String) && chunk.include?("data:")
          extract_sse_data(chunk)
        else
          chunk
        end
        
        return unless data
        
        # Process based on current state
        case @state
        when BUFFER_STATES[:idle]
          process_idle_chunk(data)
        when BUFFER_STATES[:buffering_content]
          process_content_chunk(data)
        when BUFFER_STATES[:buffering_tool_call]
          process_tool_call_chunk(data)
        end
        
        # Yield parsed content if block given and we have complete content
        if block_given? && has_complete_content?
          yield flush_complete_content
        end
      rescue => e
        Rails.logger.error "[StreamingBuffer] Error in process_chunk: #{e.message}"
        Rails.logger.error e.backtrace.join("\n") if ENV['DEBUG']
        # Continue processing - don't fail on single chunk errors
      end
      
      private
      
      def extract_sse_data(chunk)
        return nil unless chunk.include?("data:")
        
        lines = chunk.split("\n")
        data_line = lines.find { |l| l.start_with?("data:") }
        return nil unless data_line
        
        json_str = data_line.sub(/^data:\s*/, "")
        return nil if json_str == "[DONE]"
        
        begin
          JSON.parse(json_str)
        rescue JSON::ParserError
          nil
        end
      end
      
      def has_complete_content?
        @content_buffer.present? || @tool_calls_queue.any?
      end
      
      def flush_complete_content
        result = {
          content: @content_buffer.dup,
          tool_calls: @tool_calls_queue.dup
        }
        
        @content_buffer = ""
        @tool_calls_queue = []
        
        result
      end
      
      
      def flush_buffers
        # Flush any remaining content
        if @content_buffer.present?
          process_complete_content(@content_buffer)
          @content_buffer = ""
        end
        
        # Execute any pending tool calls
        execute_pending_tool_calls
        
        # Final progress update
        @progress = 1.0
        @state = BUFFER_STATES[:completed]
        update_progress_display(final: true)
      end
      
      private
      
      def process_idle_chunk(chunk)
        if chunk.include?('"tool_calls"') || chunk.include?('"function"')
          @state = BUFFER_STATES[:buffering_tool_call]
          @tool_call_buffer = chunk
        elsif chunk.include?('"content"')
          @state = BUFFER_STATES[:buffering_content]
          @content_buffer = chunk
        else
          # Just accumulate
          @content_buffer += chunk
        end
      end
      
      def process_content_chunk(chunk)
        @content_buffer += chunk
        
        # Check if we have a complete content block
        if looks_like_complete_content?(@content_buffer)
          process_complete_content(@content_buffer)
          @content_buffer = ""
          @state = BUFFER_STATES[:idle]
        end
      end
      
      def process_tool_call_chunk(chunk)
        @tool_call_buffer += chunk
        
        # Try to parse as complete tool call
        if looks_like_complete_tool_call?(@tool_call_buffer)
          parsed = try_parse_tool_call(@tool_call_buffer)
          if parsed
            queue_tool_call(parsed)
            @tool_call_buffer = ""
            @state = BUFFER_STATES[:idle]
            
            # Execute immediately for better UX
            execute_pending_tool_calls
          end
        end
      end
      
      def looks_like_complete_content?(buffer)
        # Check for complete JSON structure or complete sentence
        return false if buffer.blank?
        
        # Simple heuristic: has closing quotes and punctuation
        buffer.include?('"') && (
          buffer.include?('.') || 
          buffer.include?('!') || 
          buffer.include?('?') ||
          buffer.include?('"}')
        )
      end
      
      def looks_like_complete_tool_call?(buffer)
        # Check for complete tool call JSON structure
        return false if buffer.blank?
        
        # Count braces to see if JSON is complete
        open_braces = buffer.count('{')
        close_braces = buffer.count('}')
        open_brackets = buffer.count('[')
        close_brackets = buffer.count(']')
        
        open_braces == close_braces && 
        open_brackets == close_brackets &&
        open_braces > 0
      end
      
      def try_parse_tool_call(buffer)
        # Extract JSON from buffer
        json_match = buffer.match(/\{.*\}/m)
        return nil unless json_match
        
        begin
          parsed = JSON.parse(json_match[0])
          
          # Validate it has required fields
          if parsed['function'] && parsed['function']['name']
            return parsed
          elsif parsed['name'] && parsed['arguments']
            # Alternative format
            return {
              'function' => {
                'name' => parsed['name'],
                'arguments' => parsed['arguments']
              }
            }
          end
        rescue JSON::ParserError
          # Not yet complete JSON
          nil
        end
      end
      
      def queue_tool_call(tool_call)
        @tool_calls_queue << tool_call
        
        # Determine stage based on tool call
        update_stage_from_tool_call(tool_call)
      end
      
      def execute_pending_tool_calls
        while tool_call = @tool_calls_queue.shift
          execute_tool_call(tool_call)
        end
      end
      
      def execute_tool_call(tool_call)
        @state = BUFFER_STATES[:executing_tool]
        
        function_name = tool_call.dig('function', 'name')
        arguments = tool_call.dig('function', 'arguments')
        
        # Parse arguments if they're a string
        args = arguments.is_a?(String) ? JSON.parse(arguments) : arguments
        
        case function_name
        when 'create_file'
          handle_create_file_streaming(args)
        when 'update_file', 'line_replace'
          handle_update_file_streaming(args)
        when 'broadcast_progress'
          handle_progress_update(args)
        when 'finish_app'
          handle_finish_app(args)
        else
          Rails.logger.debug "[StreamingBuffer] Unknown tool: #{function_name}"
        end
        
        @state = BUFFER_STATES[:idle]
      rescue => e
        Rails.logger.error "[StreamingBuffer] Tool execution error: #{e.message}"
        @state = BUFFER_STATES[:idle]
      end
      
      def handle_create_file_streaming(args)
        path = args['path']
        content = args['content']
        file_type = args['file_type'] || determine_file_type(path)
        
        @current_file = path
        
        # Update progress with file creation
        message = "Creating #{path}..."
        @broadcaster.update(message, calculate_overall_progress)
        
        # Create or update file
        file = @app.app_files.find_by(path: path) || @app.app_files.build(path: path, team: @app.team)
        file.update!(
          content: content,
          file_type: file_type,
          size_bytes: content.bytesize
        )
        
        @files_created << path
        @lines_written += content.lines.count
        
        # Broadcast file creation with visual feedback
        broadcast_file_creation(path, file_type)
        
        Rails.logger.info "[StreamingBuffer] Created file: #{path} (#{content.bytesize} bytes)"
      end
      
      def handle_update_file_streaming(args)
        path = args['path']
        
        @current_file = path
        
        # Update progress
        message = "Updating #{path}..."
        @broadcaster.update(message, calculate_overall_progress)
        
        # Let the orchestrator handle the actual update
        # We just track progress here
        @lines_written += 10  # Estimate
        
        broadcast_file_update(path)
      end
      
      def handle_progress_update(args)
        message = args['message']
        percentage = args['percentage']
        
        # Use the AI's progress update
        if message.present?
          @broadcaster.update(message, (percentage || calculate_overall_progress) / 100.0)
        end
      end
      
      def handle_finish_app(args)
        summary = args['summary']
        
        @progress = 1.0
        @state = BUFFER_STATES[:completed]
        
        # Final success message
        @broadcaster.update("✅ #{summary || 'App generation complete!'}", 1.0)
      end
      
      def update_stage_from_tool_call(tool_call)
        function_name = tool_call.dig('function', 'name')
        args = JSON.parse(tool_call.dig('function', 'arguments') || '{}') rescue {}
        path = args['path'] || ''
        
        # Determine stage based on file being created
        if path.include?('index.html') || path.include?('.html')
          @current_stage = :structure
        elsif path.include?('.jsx') || path.include?('component')
          @current_stage = :components
        elsif path.include?('.css') || path.include?('style')
          @current_stage = :styling
        elsif function_name == 'update_file' || function_name == 'line_replace'
          @current_stage = :interactivity
        elsif function_name == 'finish_app'
          @current_stage = :polish
        end
        
        update_stage_progress
      end
      
      def update_stage_progress
        # Update progress for current stage
        @stage_progress[@current_stage] = (@stage_progress[@current_stage] || 0) + 0.1
        @stage_progress[@current_stage] = [@stage_progress[@current_stage], 1.0].min
      end
      
      def calculate_overall_progress
        # Calculate weighted progress across all stages
        total_progress = 0.0
        
        GENERATION_STAGES.each do |stage_key, stage_info|
          stage_completion = @stage_progress[stage_key] || 0
          stage_completion = 1.0 if completed_stages.include?(stage_key)
          
          total_progress += stage_completion * stage_info[:weight]
        end
        
        # Add file creation progress
        file_progress = @files_created.size / 10.0  # Assume ~10 files for typical app
        total_progress = [total_progress, file_progress].max
        
        # Ensure progress only goes up
        @progress = [@progress, total_progress, 0.95].min  # Cap at 95% until finish
        @progress
      end
      
      def completed_stages
        stages = []
        stages << :structure if @files_created.any? { |f| f.include?('.html') }
        stages << :components if @files_created.any? { |f| f.include?('.jsx') }
        stages << :styling if @files_created.any? { |f| f.include?('.css') }
        stages
      end
      
      def update_progress_display(final: false)
        if final
          message = "✅ App generation complete! Created #{@files_created.size} files"
          @broadcaster.update(message, 1.0)
        else
          stage_info = GENERATION_STAGES[@current_stage]
          stage_name = stage_info ? stage_info[:name] : 'Processing'
          
          # Create detailed progress message
          message = "#{stage_name}"
          message += " - #{@current_file}" if @current_file
          message += " (#{@files_created.size} files created)" if @files_created.any?
          
          @broadcaster.update(message, @progress)
        end
        
        # Log progress for debugging
        Rails.logger.debug "[StreamingBuffer] Progress: #{(@progress * 100).round}% - #{@current_stage} - #{@files_created.size} files"
      end
      
      def broadcast_file_creation(path, file_type)
        # Broadcast file creation event for UI updates
        Turbo::StreamsChannel.broadcast_append_to(
          "app_#{@app.id}_file_updates",
          target: "file_updates_list",
          html: render_file_update_html(path, 'created', file_type)
        )
      rescue => e
        Rails.logger.error "[StreamingBuffer] Broadcast error: #{e.message}"
      end
      
      def broadcast_file_update(path)
        Turbo::StreamsChannel.broadcast_append_to(
          "app_#{@app.id}_file_updates",
          target: "file_updates_list",
          html: render_file_update_html(path, 'updated')
        )
      rescue => e
        Rails.logger.error "[StreamingBuffer] Broadcast error: #{e.message}"
      end
      
      def render_file_update_html(path, action, file_type = nil)
        icon = file_icon_for_type(file_type)
        color = action == 'created' ? 'green' : 'blue'
        
        <<~HTML
          <div class="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400 animate-slide-in">
            <span class="text-#{color}-500">#{icon}</span>
            <span class="font-mono">#{path}</span>
            <span class="text-#{color}-500">#{action}</span>
          </div>
        HTML
      end
      
      def file_icon_for_type(file_type)
        case file_type
        when 'html' then '📄'
        when 'js', 'jsx' then '⚡'
        when 'css' then '🎨'
        when 'json' then '📋'
        else '📁'
        end
      end
      
      def process_complete_content(content)
        # Process any complete content that's not a tool call
        # This might be assistant commentary or status updates
        Rails.logger.debug "[StreamingBuffer] Processing content: #{content[0..100]}"
      end
      
      def determine_file_type(path)
        ext = File.extname(path).downcase.delete(".")
        case ext
        when "html", "htm" then "html"
        when "js", "jsx" then "js"
        when "css", "scss" then "css"
        when "json" then "json"
        else "text"
        end
      end
    end
  end
end