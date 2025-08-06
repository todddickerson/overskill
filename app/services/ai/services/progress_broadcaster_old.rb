module Ai
  module Services
    # ProgressBroadcaster - Handles all progress updates and broadcasting
    # Single responsibility: Manage progress state and updates
    class ProgressBroadcaster
      attr_reader :app, :message, :stages
      
      STAGE_EMOJIS = {
        thinking: '🤔',
        planning: '📋',
        analyzing: '🔍',
        coding: '💻',
        reviewing: '🔎',
        optimizing: '⚡',
        deploying: '🚀',
        completed: '✅',
        failed: '❌'
      }.freeze
      
      def initialize(app, message)
        @app = app
        @message = message
        @stages = []
        @current_stage = nil
        @start_time = Time.current
      end
      
      # Define stages for this operation
      def define_stages(stages_config)
        @stages = stages_config.map.with_index do |stage, index|
          {
            name: stage[:name],
            description: stage[:description],
            emoji: STAGE_EMOJIS[stage[:name]] || '🔄',
            progress_range: calculate_progress_range(index, stages_config.size),
            status: 'pending'
          }
        end
      end
      
      # Enter a new stage
      def enter_stage(stage_name)
        stage = @stages.find { |s| s[:name] == stage_name }
        return unless stage
        
        # Mark previous stage as completed
        if @current_stage
          @current_stage[:status] = 'completed'
          @current_stage[:completed_at] = Time.current
        end
        
        # Enter new stage
        @current_stage = stage
        stage[:status] = 'in_progress'
        stage[:started_at] = Time.current
        
        broadcast_progress(
          "#{stage[:emoji]} #{stage[:description]}",
          stage[:progress_range].begin
        )
      end
      
      # Update progress within current stage
      def update(message, progress_offset = 0.5)
        return unless @current_stage
        
        range = @current_stage[:progress_range]
        progress = range.begin + ((range.end - range.begin) * progress_offset)
        
        broadcast_progress(message, progress.round)
      end
      
      # Complete the entire operation
      def complete(summary = nil)
        if @current_stage
          @current_stage[:status] = 'completed'
          @current_stage[:completed_at] = Time.current
        end
        
        total_duration = Time.current - @start_time
        
        completion_message = build_completion_message(summary, total_duration)
        broadcast_progress(completion_message, 100)
        
        @message.update!(status: 'completed')
      end
      
      # Mark operation as failed
      def fail(error_message)
        if @current_stage
          @current_stage[:status] = 'failed'
          @current_stage[:failed_at] = Time.current
        end
        
        broadcast_progress(
          "❌ #{error_message}",
          @current_stage ? @current_stage[:progress_range].begin : 0
        )
        
        @message.update!(status: 'failed')
      end
      
      private
      
      def calculate_progress_range(index, total)
        segment_size = 100.0 / total
        start_progress = (index * segment_size).round
        end_progress = ((index + 1) * segment_size).round
        start_progress..end_progress
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
                   when 'completed' then '✅'
                   when 'in_progress' then '🔄'
                   when 'failed' then '❌'
                   else '⏳'
                   end
            "#{icon} #{stage[:description]}"
          end.join("\n")
          
          content += "\n**Stages:**\n#{stage_summary}"
        end
        
        @message.update!(content: content)
        broadcast_turbo_update
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
      
      def broadcast_turbo_update
        Turbo::StreamsChannel.broadcast_replace_to(
          "app_#{@app.id}_chat",
          target: "message_content_#{@message.id}",
          partial: "account/app_editors/chat_message_content",
          locals: { message: @message }
        )
      end
    end
  end
end