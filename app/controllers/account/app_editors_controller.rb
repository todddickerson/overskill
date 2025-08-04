class Account::AppEditorsController < Account::ApplicationController
  layout "editor"
  before_action :set_app
  skip_before_action :set_app, only: [:deployment_info]
  before_action :set_app_by_id, only: [:deployment_info]

  def show
    @messages = @app.app_chat_messages.order(created_at: :asc)
    @files = @app.app_files.order(:path)
    @selected_file = @files.find_by(id: params[:file_id]) || @files.first

    respond_to do |format|
      format.html do
        # For Turbo Frame requests, render just the code editor partial
        if turbo_frame_request? && turbo_frame_request_id == "code_editor"
          render partial: "account/app_editors/code_editor", locals: { file: @selected_file, app: @app }
        else
          render :show
        end
      end
      format.turbo_stream do
        if params[:file_id]
          render turbo_stream: turbo_stream.replace("code_editor",
            partial: "account/app_editors/code_editor",
            locals: {file: @selected_file, app: @app})
        end
      end
    end
  end

  def update_file
    @file = @app.app_files.find(params[:file_id])
    content = params[:app_file]&.dig(:content) || params[:content]

    if @file.update(content: content)
      # Update size based on content
      @file.update(size_bytes: content.bytesize)
      
      # Create a version for manual edits
      @app.app_versions.create!(
        team: @app.team,
        user: current_user,
        version_number: next_version_number(@app),
        changelog: "Manual edit: #{@file.path}",
        changed_files: @file.path
      )
      
      # Update preview worker with latest changes
      UpdatePreviewJob.perform_later(@app.id)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("file_#{@file.id}_status",
              partial: "account/app_editors/file_status",
              locals: {file: @file, status: "saved"}),
            turbo_stream.replace("preview_frame",
              partial: "account/app_editors/preview_frame",
              locals: {app: @app})
          ]
        end
        format.json { render json: {status: "saved"} }
      end
    else
      respond_to do |format|
        format.json { render json: {status: "error", errors: @file.errors} }
      end
    end
  end

  def create_message
    Rails.logger.info "[AppEditors#create_message] Starting message creation for app #{@app.id}"
    Rails.logger.info "[AppEditors#create_message] Message params: #{message_params.inspect}"
    
    @message = @app.app_chat_messages.build(message_params)
    @message.role = "user"
    @message.user = current_user
    
    Rails.logger.info "[AppEditors#create_message] Built message: #{@message.inspect}"

    if @message.save
      Rails.logger.info "[AppEditors#create_message] User message saved with ID: #{@message.id}"
      
      # Create initial AI response placeholder
      ai_response = @app.app_chat_messages.create!(
        role: "assistant",
        content: "Analyzing your request and planning the changes...",
        status: "planning"
      )
      Rails.logger.info "[AppEditors#create_message] AI placeholder created with ID: #{ai_response.id}"

      # Start processing
      # Use new orchestrator if feature flag is enabled
      if ENV['USE_AI_ORCHESTRATOR'] == 'true'
        Rails.logger.info "[AppEditors#create_message] Using new AI orchestrator"
        # Don't create the placeholder message - orchestrator will handle all messages
        ai_response.destroy!
        job = ProcessAppUpdateJobV2.perform_later(@message)
        Rails.logger.info "[AppEditors#create_message] ProcessAppUpdateJobV2 enqueued with job ID: #{job.job_id}"
      else
        job = ProcessAppUpdateJob.perform_later(@message)
        Rails.logger.info "[AppEditors#create_message] ProcessAppUpdateJob enqueued with job ID: #{job.job_id}"
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("chat_messages",
              partial: "account/app_editors/chat_message",
              locals: {message: @message}),
            turbo_stream.append("chat_messages",
              partial: "account/app_editors/chat_message",
              locals: {message: ai_response}),
            turbo_stream.replace("chat_form",
              partial: "account/app_editors/chat_input_wrapper",
              locals: {app: @app}),
            # Append a temporary element that will scroll the container on connection
            turbo_stream.append("chat_messages", 
              "<div data-controller='chat-scroller' data-chat-scroller-target='trigger'></div>")
          ]
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("chat_form",
            partial: "account/app_editors/chat_input_wrapper",
            locals: {app: @app, message: @message})
        end
      end
    end
  end

  def deploy
    # Check if app has files to deploy
    unless @app.app_files.any?
      render json: { error: "No files to deploy" }, status: :unprocessable_entity
      return
    end

    # Determine deployment target
    environment = params[:environment] || "production"
    
    # Queue deployment job with environment
    DeployAppJob.perform_later(@app.id, environment)

    respond_to do |format|
      format.json { render json: { message: "Deployment started", status: "deploying", environment: environment } }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("deploy_status",
          html: %Q{<span class="text-yellow-400"><i class="fas fa-spinner fa-spin mr-1"></i>Deploying to #{environment}...</span>})
      end
    end
  end

  def deployment_info
    # Get deployment URLs and visitor info
    preview_url = @app.preview_url
    production_url = @app.published_url || @app.deployment_url
    
    render json: {
      preview_url: preview_url,
      production_url: production_url,
      visitor_count: @app.visitor_count,
      daily_visitors: @app.daily_visitors,
      deployment_status: @app.deployment_status,
      last_deployed_at: @app.last_deployed_at,
      total_versions: @app.app_versions.count,
      last_updated: @app.updated_at
    }
  end
  
  def versions
    @versions = @app.app_versions.order(created_at: :desc)
    render partial: "version_history_list", locals: { app: @app, versions: @versions }
  end

  private

  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  def set_app_by_id
    @app = current_team.apps.find(params[:id])
  end

  def message_params
    params.require(:app_chat_message).permit(:content)
  end

  def next_version_number(app)
    last_version = app.app_versions.order(created_at: :desc).first
    if last_version
      parts = last_version.version_number.split(".")
      parts[-1] = (parts[-1].to_i + 1).to_s
      parts.join(".")
    else
      "1.0.0"
    end
  end
end
