# Simplified V5 Broadcaster with Enhanced Logging
module Ai
  class ChatProgressBroadcasterV5
    attr_reader :chat_message, :assistant_message
    
    def initialize(chat_message, assistant_message)
      @chat_message = chat_message
      @assistant_message = assistant_message
      @start_time = Time.current
      
      log_event("BROADCASTER_INIT", {
        chat_message_id: chat_message.id,
        assistant_message_id: assistant_message.id,
        app_id: chat_message.app&.id
      })
    end
    
    # Simple status updates - just save to DB
    def broadcast_status(message)
      log_event("STATUS_UPDATE", { message: message })
      @assistant_message.update!(thinking_status: message)
    end
    
    def broadcast_phase(phase_number, phase_name, total_phases)
      status = "Phase #{phase_number}/#{total_phases}: #{phase_name}"
      log_event("PHASE_CHANGE", { 
        phase: phase_number, 
        name: phase_name, 
        total: total_phases 
      })
      @assistant_message.update!(thinking_status: status)
    end
    
    def broadcast_progress(percentage, details = nil)
      status = "Progress: #{percentage}%"
      status += " - #{details}" if details
      log_event("PROGRESS", { percentage: percentage, details: details })
      @assistant_message.update!(thinking_status: status)
    end
    
    def broadcast_complete(message, preview_url = nil)
      log_event("GENERATION_COMPLETE", { 
        message: message, 
        preview_url: preview_url,
        duration_seconds: (Time.current - @start_time).round(2)
      })
      @assistant_message.update!(
        thinking_status: nil,
        status: 'completed',
        content: message
      )
    end
    
    def broadcast_error(error_message)
      log_event("GENERATION_ERROR", { 
        error: error_message,
        duration_seconds: (Time.current - @start_time).round(2)
      })
      @assistant_message.update!(
        thinking_status: nil,
        status: 'failed',
        content: "Error: #{error_message}"
      )
    end
    
    # Log message to loop_messages array
    def add_loop_message(content, type: 'content')
      log_event("LOOP_MESSAGE", { type: type, content_preview: content[0..100] })
      @assistant_message.loop_messages << {
        'content' => content,
        'type' => type,
        'timestamp' => Time.current.iso8601
      }
      @assistant_message.save!
    end
    
    # Log tool call
    def add_tool_call(tool_name, file_path: nil, status: 'complete')
      log_event("TOOL_CALL", { 
        tool: tool_name, 
        file: file_path, 
        status: status 
      })
      @assistant_message.tool_calls << {
        'name' => tool_name,
        'file_path' => file_path,
        'status' => status,
        'timestamp' => Time.current.iso8601
      }
      @assistant_message.save!
    end
    
    private
    
    def log_event(event_type, details = {})
      # Format for easy grep filtering: [V5_EVENT]
      Rails.logger.info "[V5_EVENT] #{event_type} | #{format_details(details)}"
    end
    
    def format_details(details)
      details.map { |k, v| "#{k}=#{v.to_s.truncate(100)}" }.join(" | ")
    end
  end
end