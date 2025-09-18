# ChatProgressBroadcasterV2 - Enhanced broadcaster for agent loop feedback
module Ai
  class ChatProgressBroadcasterV2
    attr_reader :chat_message

    def initialize(chat_message)
      @chat_message = chat_message
      @channel = "chat_progress_#{chat_message.id}"
    end

    def broadcast_phase(phase_number, phase_name, total_phases)
      broadcast(
        type: "phase_update",
        phase: phase_number,
        total_phases: total_phases,
        phase_name: phase_name,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_status(message, details = nil)
      broadcast(
        type: "status_update",
        message: message,
        details: details,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_progress(percentage, message = nil)
      broadcast(
        type: "progress_update",
        progress: percentage,
        message: message,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_tool_execution(tool_name, status, details = nil)
      broadcast(
        type: "tool_execution",
        tool: tool_name,
        status: status, # 'starting', 'running', 'completed', 'failed'
        details: details,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_file_created(file_path, language)
      broadcast(
        type: "file_created",
        file_path: file_path,
        language: language,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_error(message, details = nil)
      broadcast(
        type: "error",
        message: message,
        details: details,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_complete(message, preview_url = nil)
      broadcast(
        type: "complete",
        message: message,
        preview_url: preview_url,
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_iteration(iteration_number, total_iterations, goals_progress)
      broadcast(
        type: "iteration_update",
        iteration: iteration_number,
        total_iterations: total_iterations,
        goals_completed: goals_progress[:completed],
        goals_total: goals_progress[:total_goals],
        goals_percentage: goals_progress[:completion_percentage],
        timestamp: Time.current.iso8601
      )
    end

    def broadcast_thinking(message)
      broadcast(
        type: "thinking",
        message: message,
        timestamp: Time.current.iso8601
      )
    end

    private

    def broadcast(data)
      ActionCable.server.broadcast(@channel, data)

      # Also log for debugging
      Rails.logger.debug "[ChatProgressBroadcasterV2] Broadcasting: #{data.inspect}"
    end
  end
end
