# Enhanced Chat Progress Broadcaster with Turbo Streams and Rails 8 patterns
module Ai
  class ChatProgressBroadcasterV2
    include ActionView::RecordIdentifier
    include ActionView::Helpers::TagHelper
    
    attr_reader :chat_message, :app, :channel
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @channel = "ChatChannel:#{chat_message.id}"
      @start_time = Time.current
    end
    
    # Main broadcast methods that use Turbo Streams and CableReady
    
    def broadcast_phase(phase_number, phase_name, total_phases = 6)
      # Use Turbo Streams for updates - use app channel that frontend subscribes to
      Turbo::StreamsChannel.broadcast_update_to(
        "app_#{@app.id}_chat",
        target: "chat-progress-#{chat_message.id}",
        html: render_progress_bar(phase_number, total_phases, phase_name)
      )
      
      # Add phase to timeline
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{@app.id}_chat",
        target: "chat-timeline-#{chat_message.id}",
        html: render_phase_item(phase_number, phase_name, "in_progress")
      )
      
      # Also broadcast via Action Cable for custom handling
      ActionCable.server.broadcast(
        "app_#{@app.id}_chat",
        {
          action: 'update_progress',
          phase: phase_number,
          phase_name: phase_name,
          total: total_phases,
          html: render_progress_bar(phase_number, total_phases, phase_name)
        }
      )
    end
    
    def broadcast_file_operation(operation, file_path, content_preview = nil, status = "pending")
      file_id = "file_#{Digest::MD5.hexdigest(file_path)}"
      
      case operation
      when :creating
        # Add file to tree with pending status
        Turbo::StreamsChannel.broadcast_append_to(
          "app_#{@app.id}_chat",
          target: "file-tree-#{chat_message.id}",
          html: render_file_tree_item(file_path, "creating")
        )
        
        # Show code preview if provided
        if content_preview
          Turbo::StreamsChannel.broadcast_update_to(
            "app_#{@app.id}_chat",
            target: "code-preview-#{chat_message.id}",
            html: render_code_preview(file_path, content_preview)
          )
        end
        
      when :created
        # Update file status with success
        Turbo::StreamsChannel.broadcast_update_to(
          "app_#{@app.id}_chat",
          target: "#{file_id}-status",
          html: render_file_status("created")
        )
        
        # Broadcast custom event for animation
        ActionCable.server.broadcast(
          "app_#{@app.id}_chat",
          {
            action: 'add_file',
            file_id: file_id,
            status: 'created'
          }
        )
        
      when :updated
        # Show diff preview
        Turbo::StreamsChannel.broadcast_update_to(
          "app_#{@app.id}_chat",
          target: "diff-preview-#{chat_message.id}",
          html: render_diff_preview(file_path, content_preview)
        )
        
      when :failed
        # Mark file as failed
        Turbo::StreamsChannel.broadcast_update_to(
          "app_#{@app.id}_chat",
          target: "#{file_id}-status",
          html: render_file_status("failed", content_preview)
        )
      end
    end
    
    def broadcast_dependency_check(dependencies, missing = [], resolved = [])
      Turbo::StreamsChannel.broadcast_update_to(
        "app_#{@app.id}_chat",
        target: "dependency-panel-#{chat_message.id}",
        html: render_dependency_panel(dependencies, missing, resolved)
      )
      
      # Add notification for missing dependencies
      if missing.any?
        Turbo::StreamsChannel.broadcast_append_to(
          "app_#{@app.id}_chat",
          target: "chat-notifications-#{chat_message.id}",
          html: render_notification(
            "Missing dependencies detected: #{missing.join(', ')}",
            type: "warning",
            action: "auto_install"
          )
        )
      end
    end
    
    def broadcast_build_output(output_line, stream_type = :stdout)
      # Stream build output in real-time
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{@app.id}_chat",
        target: "build-output-#{chat_message.id}",
        html: render_build_output_line(output_line, stream_type)
      )
      
      # Send scroll event via Action Cable
      ActionCable.server.broadcast(
        "app_#{@app.id}_chat",
        {
          action: 'update_build_output',
          line: output_line,
          stream: stream_type
        }
      )
    end
    
    def broadcast_error(error_message, recovery_suggestions = [], technical_details = nil)
      Turbo::StreamsChannel.broadcast_update_to(
        "app_#{@app.id}_chat",
        target: "error-panel-#{chat_message.id}",
        html: render_error_panel(error_message, recovery_suggestions, technical_details)
      )
      
      # Send error event for animation
      ActionCable.server.broadcast(
        "app_#{@app.id}_chat",
        {
          action: 'show_error',
          message: error_message
        }
      )
    end
    
    def broadcast_completion(success: true, stats: {})
      elapsed_time = Time.current - @start_time
      
      Turbo::StreamsChannel.broadcast_update_to(
        "app_#{@app.id}_chat",
        target: "chat-status-#{chat_message.id}",
        html: render_completion_status(success, elapsed_time, stats)
      )
      
      # Send completion event
      if success
        ActionCable.server.broadcast(
          "app_#{@app.id}_chat",
          {
            action: 'dispatch_event',
            event_name: 'generation:complete:success',
            stats: stats
          }
        )
      end
    end
    
    # Interactive controls
    
    def request_user_approval(changes, callback_id)
      Turbo::StreamsChannel.broadcast_update_to(
        "app_#{@app.id}_chat",
        target: "approval-panel-#{chat_message.id}",
        html: render_approval_panel(changes, callback_id)
      )
      
      ActionCable.server.broadcast(
        "app_#{@app.id}_chat",
        {
          action: 'dispatch_event',
          event_name: 'approval:requested',
          callback_id: callback_id
        }
      )
    end
    
    private
    
    # Render methods that use Rails partials
    
    def render_progress_bar(current, total, label)
      ApplicationController.render(
        partial: "chat_messages/components/progress_bar",
        locals: {
          current: current,
          total: total,
          label: label,
          percentage: (current.to_f / total * 100).round
        }
      )
    end
    
    def render_phase_item(phase_number, phase_name, status)
      ApplicationController.render(
        partial: "chat_messages/components/phase_item",
        locals: {
          phase_number: phase_number,
          phase_name: phase_name,
          status: status,
          timestamp: Time.current
        }
      )
    end
    
    def render_file_tree_item(file_path, status)
      ApplicationController.render(
        partial: "chat_messages/components/file_tree_item",
        locals: {
          file_path: file_path,
          status: status,
          file_type: detect_file_type(file_path),
          file_id: "file_#{Digest::MD5.hexdigest(file_path)}"
        }
      )
    end
    
    def render_file_status(status, message = nil)
      ApplicationController.render(
        partial: "chat_messages/components/file_status",
        locals: {
          status: status,
          message: message
        }
      )
    end
    
    def render_code_preview(file_path, content)
      ApplicationController.render(
        partial: "chat_messages/components/code_preview",
        locals: {
          file_path: file_path,
          content: content,
          language: detect_language(file_path)
        }
      )
    end
    
    def render_diff_preview(file_path, changes)
      ApplicationController.render(
        partial: "chat_messages/components/diff_preview",
        locals: {
          file_path: file_path,
          changes: changes
        }
      )
    end
    
    def render_dependency_panel(all_deps, missing, resolved)
      ApplicationController.render(
        partial: "chat_messages/components/dependency_panel",
        locals: {
          dependencies: all_deps,
          missing: missing,
          resolved: resolved
        }
      )
    end
    
    def render_build_output_line(line, stream_type)
      ApplicationController.render(
        partial: "chat_messages/components/build_output_line",
        locals: {
          line: line,
          stream_type: stream_type,
          timestamp: Time.current.strftime("%H:%M:%S.%L")
        }
      )
    end
    
    def render_error_panel(message, suggestions, details)
      ApplicationController.render(
        partial: "chat_messages/components/error_panel",
        locals: {
          message: message,
          suggestions: suggestions,
          technical_details: details,
          show_technical: false
        }
      )
    end
    
    def render_notification(message, type: "info", action: nil)
      ApplicationController.render(
        partial: "chat_messages/components/notification",
        locals: {
          message: message,
          type: type,
          action: action,
          id: SecureRandom.hex(8)
        }
      )
    end
    
    def render_approval_panel(changes, callback_id)
      ApplicationController.render(
        partial: "chat_messages/components/approval_panel",
        locals: {
          changes: changes,
          callback_id: callback_id,
          chat_message: chat_message
        }
      )
    end
    
    def render_completion_status(success, elapsed_time, stats)
      ApplicationController.render(
        partial: "chat_messages/components/completion_status",
        locals: {
          success: success,
          elapsed_time: elapsed_time,
          stats: stats
        }
      )
    end
    
    # Helper methods
    
    def detect_file_type(path)
      case File.extname(path)
      when '.js', '.jsx', '.ts', '.tsx'
        'javascript'
      when '.rb'
        'ruby'
      when '.css', '.scss'
        'stylesheet'
      when '.json'
        'json'
      when '.md'
        'markdown'
      else
        'text'
      end
    end
    
    def detect_language(path)
      File.extname(path).delete('.')
    end
  end
end