module Ai
  module Services
    # ProgressBroadcaster - Handles all progress updates and broadcasting
    # FIXED VERSION - Uses assistant messages, doesn't modify user messages
    class ProgressBroadcaster
      attr_reader :app, :message, :stages

      STAGE_EMOJIS = {
        thinking: "🤔",
        planning: "📋",
        analyzing: "🔍",
        coding: "💻",
        reviewing: "🔎",
        optimizing: "⚡",
        deploying: "🚀",
        completed: "✅",
        failed: "❌"
      }.freeze

      def initialize(app, message)
        @app = app
        @message = message  # This is the USER message - we should NOT modify it!
        @stages = []
        @current_stage = nil
        @start_time = Time.current
        @assistant_message = nil
      end

      # Define stages for this operation
      def define_stages(stages_config)
        @stages = stages_config.map.with_index do |stage, index|
          {
            name: stage[:name],
            description: stage[:description],
            emoji: STAGE_EMOJIS[stage[:name]] || "🔄",
            progress_range: calculate_progress_range(index, stages_config.size),
            status: "pending"
          }
        end
      end

      # Enter a new stage
      def enter_stage(stage_name)
        stage = @stages.find { |s| s[:name] == stage_name }
        return unless stage

        # Mark previous stage as completed
        if @current_stage
          @current_stage[:status] = "completed"
          @current_stage[:completed_at] = Time.current
        end

        # Set new current stage
        @current_stage = stage
        stage[:status] = "in_progress"
        stage[:started_at] = Time.current

        # Broadcast progress
        progress = stage[:progress_range].begin
        broadcast_progress("#{stage[:emoji]} #{stage[:description]}", progress)
      end

      # Update progress within current stage
      def update(status_text = nil, progress_within_stage = 0.5)
        return unless @current_stage

        range = @current_stage[:progress_range]
        progress = range.begin + (range.end - range.begin) * progress_within_stage

        text = status_text || "#{@current_stage[:emoji]} #{@current_stage[:description]}"
        broadcast_progress(text, progress)
      end

      # Complete the operation successfully
      def complete(summary = nil)
        if @current_stage
          @current_stage[:status] = "completed"
          @current_stage[:completed_at] = Time.current
        end

        total_duration = Time.current - @start_time

        completion_message = build_completion_message(summary, total_duration)
        broadcast_progress(completion_message, 100)

        # Update the assistant message status, not the user message!
        assistant_msg = find_or_create_assistant_message
        assistant_msg.update!(status: "completed")
      end

      # Mark operation as failed
      def fail(error_message)
        if @current_stage
          @current_stage[:status] = "failed"
          @current_stage[:failed_at] = Time.current
        end

        broadcast_progress(
          "❌ #{error_message}",
          @current_stage ? @current_stage[:progress_range].begin : 0
        )

        # Update the assistant message status, not the user message!
        assistant_msg = find_or_create_assistant_message
        assistant_msg.update!(status: "failed")
      end

      private

      def calculate_progress_range(index, total)
        segment_size = 100.0 / total
        start_progress = index * segment_size
        end_progress = (index + 1) * segment_size
        (start_progress.round..end_progress.round)
      end

      def broadcast_progress(status_text, progress)
        # Build progress bar
        bar_length = 20
        filled = (bar_length * progress / 100.0).round
        empty = bar_length - filled
        progress_bar = "█" * filled + "░" * empty

        # Build content
        content = <<~CONTENT
          **🚀 Progress Update**
          
          #{status_text}
          
          `#{progress_bar}` #{progress}%
        CONTENT

        # Add stage summary if available
        if @stages.any?
          stage_summary = @stages.map do |stage|
            icon = case stage[:status]
            when "completed" then "✅"
            when "in_progress" then "🔄"
            when "failed" then "❌"
            else "⏳"
            end
            "#{icon} #{stage[:description]}"
          end.join("\n")

          content += "\n**Stages:**\n#{stage_summary}"
        end

        # Update ASSISTANT message, not user message
        assistant_msg = find_or_create_assistant_message
        assistant_msg.update!(content: content)
        broadcast_turbo_update(assistant_msg)
      end

      def build_completion_message(summary, duration)
        message = "✅ **Operation Complete!**\n\n"

        if summary
          message += summary + "\n\n"
        end

        message += "Time taken: #{duration.round(1)} seconds\n\n"

        # Add stage timing breakdown
        if @stages.any?
          message += "**Stage Breakdown:**\n"
          @stages.each do |stage|
            if stage[:started_at] && stage[:completed_at]
              stage_time = (stage[:completed_at] - stage[:started_at]).round(1)
              message += "#{stage[:emoji]} #{stage[:description]}: #{stage_time}s\n"
            end
          end
        end

        message
      end

      def broadcast_turbo_update(message)
        # Use Turbo Streams directly
        Turbo::StreamsChannel.broadcast_replace_to(
          "app_#{@app.id}_chat",
          target: "app_chat_message_#{message.id}",
          partial: "account/app_editors/chat_message",
          locals: {message: message}
        )
      rescue => e
        Rails.logger.error "[ProgressBroadcaster] Broadcast failed: #{e.message}"
        Rails.logger.error "Ensure Redis is running and ActionCable is configured"
        # Don't fail the whole operation for broadcast issues
      end

      def find_or_create_assistant_message
        @assistant_message ||= begin
          # Find existing assistant message after user message
          existing = @app.app_chat_messages
            .where(role: "assistant")
            .where("created_at >= ?", @message.created_at)
            .order(created_at: :asc)
            .first

          existing || @app.app_chat_messages.create!(
            role: "assistant",
            content: "Processing your request...",
            status: "executing"
          )
        end
      end
    end
  end
end
