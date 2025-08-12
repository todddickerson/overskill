# Enhanced Chat Progress Broadcaster with CableReady and Rails 8 patterns
module Ai
  class ChatProgressBroadcasterV2
    include CableReady::Broadcaster
    
    attr_reader :chat_message, :channel
    
    def initialize(chat_message)
      @chat_message = chat_message
      @channel = "ChatChannel:#{chat_message.id}"
      @start_time = Time.current
    end
    
    # Main broadcast methods that use Turbo Streams and CableReady
    
    def broadcast_phase(phase_number, phase_name, total_phases = 6)
      # Update main progress bar
      cable_ready[channel].morph(
        selector: "#chat-progress-#{chat_message.id}",
        html: render_progress_bar(phase_number, total_phases, phase_name)
      )
      
      # Add phase to timeline with animation
      cable_ready[channel].append(
        selector: "#chat-timeline-#{chat_message.id}",
        html: render_phase_item(phase_number, phase_name, "in_progress")
      )
      
      # Broadcast the updates
      cable_ready.broadcast
      
      # Also send via Turbo Stream for redundancy
      broadcast_turbo_stream(
        target: "chat_message_#{chat_message.id}",
        partial: "chat_messages/progress_update",
        locals: { 
          phase: phase_number, 
          phase_name: phase_name,
          total: total_phases 
        }
      )
    end
    
    def broadcast_file_operation(operation, file_path, content_preview = nil, status = "pending")
      file_id = "file_#{Digest::MD5.hexdigest(file_path)}"
      
      case operation
      when :creating
        # Add file to tree with pending status
        cable_ready[channel].append(
          selector: "#file-tree-#{chat_message.id}",
          html: render_file_tree_item(file_path, "creating")
        )
        
        # Show code preview with syntax highlighting
        if content_preview
          cable_ready[channel].morph(
            selector: "#code-preview-#{chat_message.id}",
            html: render_code_preview(file_path, content_preview)
          )
        end
        
      when :created
        # Update file status with success animation
        cable_ready[channel].add_css_class(
          selector: "##{file_id}",
          name: "animate-pulse-once bg-green-50 dark:bg-green-900/20"
        )
        cable_ready[channel].morph(
          selector: "##{file_id}-status",
          html: render_file_status("created")
        )
        
      when :updated
        # Show diff preview with animations
        cable_ready[channel].morph(
          selector: "#diff-preview-#{chat_message.id}",
          html: render_diff_preview(file_path, content_preview)
        )
        
      when :failed
        # Mark file as failed with error styling
        cable_ready[channel].add_css_class(
          selector: "##{file_id}",
          name: "bg-red-50 dark:bg-red-900/20"
        )
        cable_ready[channel].morph(
          selector: "##{file_id}-status",
          html: render_file_status("failed", content_preview) # error message
        )
      end
      
      cable_ready.broadcast
    end
    
    def broadcast_dependency_check(dependencies, missing = [], resolved = [])
      cable_ready[channel].morph(
        selector: "#dependency-panel-#{chat_message.id}",
        html: render_dependency_panel(dependencies, missing, resolved)
      )
      
      # Add subtle notification for missing dependencies
      if missing.any?
        cable_ready[channel].append(
          selector: "#chat-notifications-#{chat_message.id}",
          html: render_notification(
            "Missing dependencies detected: #{missing.join(', ')}",
            type: "warning",
            action: "auto_install"
          )
        )
      end
      
      cable_ready.broadcast
    end
    
    def broadcast_build_output(output_line, stream_type = :stdout)
      # Stream build output in real-time with proper formatting
      cable_ready[channel].append(
        selector: "#build-output-#{chat_message.id}",
        html: render_build_output_line(output_line, stream_type)
      )
      
      # Auto-scroll to bottom
      cable_ready[channel].dispatch_event(
        selector: "#build-output-#{chat_message.id}",
        name: "build:output:scroll"
      )
      
      cable_ready.broadcast
    end
    
    def broadcast_error(error_message, recovery_suggestions = [], technical_details = nil)
      cable_ready[channel].morph(
        selector: "#error-panel-#{chat_message.id}",
        html: render_error_panel(error_message, recovery_suggestions, technical_details)
      )
      
      # Add shake animation to draw attention
      cable_ready[channel].add_css_class(
        selector: "#error-panel-#{chat_message.id}",
        name: "animate-shake"
      )
      
      cable_ready.broadcast
    end
    
    def broadcast_completion(success: true, stats: {})
      elapsed_time = Time.current - @start_time
      
      cable_ready[channel].morph(
        selector: "#chat-status-#{chat_message.id}",
        html: render_completion_status(success, elapsed_time, stats)
      )
      
      # Add celebration animation if successful
      if success
        cable_ready[channel].dispatch_event(
          selector: "#chat-message-#{chat_message.id}",
          name: "generation:complete:success"
        )
      end
      
      cable_ready.broadcast
    end
    
    # Interactive controls
    
    def request_user_approval(changes, callback_id)
      cable_ready[channel].morph(
        selector: "#approval-panel-#{chat_message.id}",
        html: render_approval_panel(changes, callback_id)
      )
      
      cable_ready[channel].dispatch_event(
        selector: "#approval-panel-#{chat_message.id}",
        name: "approval:requested"
      )
      
      cable_ready.broadcast
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
    
    def broadcast_turbo_stream(target:, partial:, locals: {})
      Turbo::StreamsChannel.broadcast_update_to(
        "chat_message_#{chat_message.id}",
        target: target,
        partial: partial,
        locals: locals
      )
    end
  end
end