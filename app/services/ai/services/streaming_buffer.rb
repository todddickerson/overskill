module Ai
  module Services
    # StreamingBuffer - Buffers streaming AI responses and broadcasts meaningful updates
    class StreamingBuffer
      attr_reader :app, :message, :buffer, :last_broadcast_time

      BROADCAST_INTERVAL = 0.5 # seconds between broadcasts
      MIN_BUFFER_SIZE = 50 # minimum characters before broadcasting

      def initialize(app, message)
        @app = app
        @message = message
        @buffer = ""
        @tool_buffer = nil
        @last_broadcast_time = Time.current
        @partial_json = ""
        @in_code_block = false
        @code_block_buffer = ""
        @assistant_message = nil
      end

      # Add chunk to buffer and broadcast if appropriate
      def add_chunk(chunk)
        @buffer += chunk

        # Detect and handle different content types
        if detecting_json?(chunk)
          handle_json_chunk(chunk)
        elsif in_code_block?
          handle_code_chunk(chunk)
        else
          handle_text_chunk(chunk)
        end
      end

      # Force broadcast current buffer
      def flush
        broadcast_update if @buffer.present?
        @buffer = ""
      end

      # Complete the streaming and finalize message
      def complete(final_content = nil)
        content = final_content || @buffer

        if @assistant_message
          @assistant_message.update!(
            content: content,
            status: "completed"
          )
        else
          @assistant_message = create_assistant_message(content, "completed")
        end

        broadcast_final_update
        @assistant_message
      end

      # Handle error during streaming
      def error(error_message)
        content = if @buffer.present?
          "#{@buffer}\n\n❌ Error: #{error_message}"
        else
          "❌ Error: #{error_message}"
        end

        if @assistant_message
          @assistant_message.update!(
            content: content,
            status: "failed"
          )
        else
          @assistant_message = create_assistant_message(content, "failed")
        end

        broadcast_final_update
      end

      private

      def detecting_json?(chunk)
        chunk.include?("{") || chunk.include?("[") || @partial_json.present?
      end

      def in_code_block?
        @in_code_block || @buffer.include?("```")
      end

      def handle_json_chunk(chunk)
        @partial_json += chunk

        # Try to parse complete JSON objects
        if valid_json?(@partial_json)
          # We have a complete JSON object
          process_json(@partial_json)
          @partial_json = ""
        elsif @partial_json.length > 5000
          # Too much accumulated, probably not JSON
          handle_text_chunk(@partial_json)
          @partial_json = ""
        end
      end

      def handle_code_chunk(chunk)
        # Check for code block markers
        if chunk.include?("```")
          @in_code_block = !@in_code_block

          if !@in_code_block && @code_block_buffer.present?
            # Code block completed, broadcast it
            broadcast_code_block(@code_block_buffer)
            @code_block_buffer = ""
          end
        elsif @in_code_block
          @code_block_buffer += chunk
        end

        # Still broadcast text updates periodically
        maybe_broadcast_update
      end

      def handle_text_chunk(chunk)
        # For regular text, broadcast periodically
        maybe_broadcast_update
      end

      def maybe_broadcast_update
        # Broadcast if we have enough content and enough time has passed
        should_broadcast = (
          @buffer.length >= MIN_BUFFER_SIZE &&
          Time.current - @last_broadcast_time >= BROADCAST_INTERVAL
        ) || @buffer.include?("\n\n") # Or if we have paragraph breaks

        broadcast_update if should_broadcast
      end

      def broadcast_update
        return if @buffer.blank?

        # Format content for display
        display_content = format_content(@buffer)

        # Create or update assistant message
        if @assistant_message
          @assistant_message.update!(
            content: display_content,
            status: "executing"
          )
        else
          @assistant_message = create_assistant_message(display_content, "executing")
        end

        # Broadcast via Turbo
        begin
          Turbo::StreamsChannel.broadcast_replace_to(
            "app_#{@app.id}_chat",
            target: "app_chat_message_#{@assistant_message.id}",
            partial: "account/app_editors/chat_message",
            locals: {message: @assistant_message}
          )
        rescue => e
          Rails.logger.error "[StreamingBuffer] Broadcast failed: #{e.message}"
        end

        @last_broadcast_time = Time.current
      end

      def broadcast_code_block(code)
        # Special handling for code blocks
        Rails.logger.info "[StreamingBuffer] Broadcasting code block: #{code.lines.first}..."

        # Could trigger file creation/update here
        # For now, just include in message
        maybe_broadcast_update
      end

      def broadcast_final_update
        Turbo::StreamsChannel.broadcast_replace_to(
          "app_#{@app.id}_chat",
          target: "app_chat_message_#{@assistant_message.id}",
          partial: "account/app_editors/chat_message",
          locals: {message: @assistant_message}
        )

        # Also refresh the chat form
        Turbo::StreamsChannel.broadcast_replace_to(
          "app_#{@app.id}_chat",
          target: "chat_form",
          partial: "account/app_editors/chat_input_wrapper",
          locals: {app: @app}
        )
      rescue => e
        Rails.logger.error "[StreamingBuffer] Final broadcast failed: #{e.message}"
      end

      def create_assistant_message(content, status)
        @app.app_chat_messages.create!(
          role: "assistant",
          content: content,
          status: status
        )
      end

      def format_content(content)
        # Clean up incomplete sentences at the end
        if content.length > 100 && !content.end_with?(".", "!", "?", "\n")
          # Find last complete sentence
          last_sentence = content.rindex(/[.!?]\s/)
          if last_sentence && last_sentence > content.length * 0.7
            content = content[0..last_sentence]
          else
            content += "..."
          end
        end

        content
      end

      def valid_json?(str)
        JSON.parse(str)
        true
      rescue JSON::ParserError
        false
      end

      def process_json(json_str)
        # Handle structured JSON responses

        data = JSON.parse(json_str)

        # Check if it's a tool call result
        if data["tool_calls"] || data["function_call"]
          Rails.logger.info "[StreamingBuffer] Received tool call in stream"
          # Tool calls will be handled by the orchestrator
        elsif data["files"] || data["operations"]
          Rails.logger.info "[StreamingBuffer] Received file operations in stream"
          # File operations detected
        end
      rescue => e
        Rails.logger.warn "[StreamingBuffer] Failed to process JSON: #{e.message}"
      end
    end
  end
end
