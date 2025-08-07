# New version that uses the orchestrator for better user feedback
class ProcessAppUpdateJobV2 < ApplicationJob
  queue_as :ai_generation
  
  # Set a 10 minute timeout for the entire job to handle complex requests
  # We'll use incremental updates to keep users informed during long operations
  around_perform do |job, block|
    timeout_start = Time.current
    Rails.logger.info "[ProcessAppUpdateJobV2] ⏳ Starting 10-minute timeout wrapper at #{timeout_start}"
    
    Timeout.timeout(600) do  # 10 minutes
      block.call
    end
    
    Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Job completed within timeout (#{(Time.current - timeout_start).round(2)}s)"
    
  rescue Timeout::Error
    timeout_duration = Time.current - timeout_start
    Rails.logger.error "[ProcessAppUpdateJobV2] ⏰ TIMEOUT ERROR: Job exceeded 10 minutes (actual: #{timeout_duration.round(2)}s)"
    chat_message = job.arguments.first
    Rails.logger.error "[ProcessAppUpdateJobV2] 📋 Timeout context - Message ID: #{chat_message&.id}, App ID: #{chat_message&.app_id}"
    handle_timeout_error(chat_message)
  end
  
  def perform(chat_message)
    Rails.logger.info "[ProcessAppUpdateJobV2] 🚀 Starting orchestrated update for message ##{chat_message.id}"
    Rails.logger.info "[ProcessAppUpdateJobV2] 📱 App: #{chat_message.app.name} (ID: #{chat_message.app.id})"
    Rails.logger.info "[ProcessAppUpdateJobV2] 💬 Message content: #{chat_message.content.truncate(200)}"
    Rails.logger.info "[ProcessAppUpdateJobV2] 👤 Team: #{chat_message.app.team.name} (ID: #{chat_message.app.team.id})"
    
    start_time = Time.current
    Rails.logger.info "[ProcessAppUpdateJobV2] ⏰ Job started at: #{start_time}"
    
    # Try streaming orchestrator first for better real-time feedback
    begin
      Rails.logger.info "[ProcessAppUpdateJobV2] 🌊 Attempting streaming orchestrator..."
      orchestrator_start = Time.current
      orchestrator = Ai::AppUpdateOrchestratorStreaming.new(chat_message)
      Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Streaming orchestrator initialized in #{(Time.current - orchestrator_start).round(2)}s"
      
      Rails.logger.info "[ProcessAppUpdateJobV2] 🎯 Executing streaming orchestrator..."
      execute_start = Time.current
      orchestrator.execute!
      execution_time = Time.current - execute_start
      Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Streaming orchestrator executed successfully in #{execution_time.round(2)}s"
      
    rescue => e
      Rails.logger.warn "[ProcessAppUpdateJobV2] ⚠️ Streaming orchestrator failed: #{e.class.name}: #{e.message}"
      Rails.logger.warn "[ProcessAppUpdateJobV2] 📍 Error location: #{e.backtrace&.first}"
      
      Rails.logger.info "[ProcessAppUpdateJobV2] 🔄 Falling back to v2 orchestrator..."
      fallback_start = Time.current
      
      begin
        orchestrator = Ai::AppUpdateOrchestratorV2.new(chat_message)
        Rails.logger.info "[ProcessAppUpdateJobV2] ✅ V2 orchestrator initialized in #{(Time.current - fallback_start).round(2)}s"
        
        execute_fallback_start = Time.current
        orchestrator.execute!
        fallback_execution_time = Time.current - execute_fallback_start
        Rails.logger.info "[ProcessAppUpdateJobV2] ✅ V2 orchestrator executed successfully in #{fallback_execution_time.round(2)}s"
        
      rescue => fallback_error
        Rails.logger.error "[ProcessAppUpdateJobV2] ❌ V2 orchestrator also failed: #{fallback_error.class.name}: #{fallback_error.message}"
        raise fallback_error
      end
    end
    
    # Update database tables if needed
    update_database_tables(chat_message.app)
    
    total_time = Time.current - start_time
    Rails.logger.info "[ProcessAppUpdateJobV2] 🎉 Orchestrated update completed successfully!"
    Rails.logger.info "[ProcessAppUpdateJobV2] ⏱️ Total execution time: #{total_time.round(2)}s"
    
  rescue => e
    error_time = Time.current - start_time
    Rails.logger.error "[ProcessAppUpdateJobV2] 💥 FATAL ERROR after #{error_time.round(2)}s: #{e.class.name}: #{e.message}"
    Rails.logger.error "[ProcessAppUpdateJobV2] 📋 Full backtrace:"
    e.backtrace.each_with_index do |line, index|
      Rails.logger.error "[ProcessAppUpdateJobV2]   #{index.to_s.rjust(3)}: #{line}"
    end
    Rails.logger.error "[ProcessAppUpdateJobV2] 🚨 Triggering error handler..."
    handle_error(chat_message, e.message)
  end
  
  private
  
  def update_database_tables(app)
    Rails.logger.info "[ProcessAppUpdateJobV2] 🗄️ Checking for database table updates..."
    
    begin
      # Use table update service to add any new tables or columns
      update_service = Supabase::TableUpdateService.new(app)
      result = update_service.update_tables_for_app!
      
      if result[:success]
        if result[:new_tables].any?
          Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Created new tables: #{result[:new_tables].join(', ')}"
        end
        if result[:updated_tables].any?
          Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Updated tables: #{result[:updated_tables].join(', ')}"
        end
      else
        Rails.logger.warn "[ProcessAppUpdateJobV2] ⚠️ Table update failed: #{result[:error]}"
      end
    rescue => e
      Rails.logger.error "[ProcessAppUpdateJobV2] ❌ Database update error: #{e.message}"
      # Don't fail the job - tables will be created on first use
    end
  end
  
  def handle_timeout_error(chat_message)
    Rails.logger.error "[ProcessAppUpdateJobV2] ⏰ TIMEOUT: Job exceeded 10 minute limit for message ##{chat_message.id}"
    Rails.logger.error "[ProcessAppUpdateJobV2] 📱 App: #{chat_message.app.name} (ID: #{chat_message.app.id})"
    Rails.logger.error "[ProcessAppUpdateJobV2] 💬 Timed out message: #{chat_message.content.truncate(100)}"
    
    error_response = chat_message.app.app_chat_messages.create!(
      role: "assistant",
      content: "⏱️ This request took too long to process (over 10 minutes) and was automatically cancelled.\n\nPlease try breaking your request into smaller, more specific changes.",
      status: "failed"
    )
    
    Rails.logger.info "[ProcessAppUpdateJobV2] 💌 Created timeout error message ##{error_response.id}"
    broadcast_error(chat_message, error_response)
  end
  
  def handle_error(chat_message, error_message)
    Rails.logger.error "[ProcessAppUpdateJobV2] 🚨 HANDLING ERROR: #{error_message.truncate(200)}"
    Rails.logger.error "[ProcessAppUpdateJobV2] 📱 App: #{chat_message.app.name} (ID: #{chat_message.app.id})"
    Rails.logger.error "[ProcessAppUpdateJobV2] 💬 Original message: #{chat_message.content.truncate(100)}"
    
    error_response = chat_message.app.app_chat_messages.create!(
      role: "assistant",
      content: "❌ I encountered an error: #{error_message}\n\nPlease try rephrasing your request or contact support if the issue persists.",
      status: "failed"
    )
    
    Rails.logger.info "[ProcessAppUpdateJobV2] 💌 Created error response message ##{error_response.id}"
    broadcast_error(chat_message, error_response)
  end
  
  def broadcast_error(user_message, error_message)
    Rails.logger.info "[ProcessAppUpdateJobV2] 📡 Broadcasting error message to app_#{user_message.app_id}_chat"
    Rails.logger.info "[ProcessAppUpdateJobV2] 💬 Error message ID: #{error_message.id}, Status: #{error_message.status}"
    
    # Broadcast the error message
    Turbo::StreamsChannel.broadcast_append_to(
      "app_#{user_message.app_id}_chat",
      target: "chat_messages",
      partial: "account/app_editors/chat_message",
      locals: {message: error_message}
    )
    Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Error message broadcast completed"
    
    # Re-enable the chat form
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{user_message.app_id}_chat",
      target: "chat_form",
      partial: "account/app_editors/chat_input_wrapper",
      locals: {app: user_message.app}
    )
    Rails.logger.info "[ProcessAppUpdateJobV2] ✅ Chat form re-enabled"
  end
end