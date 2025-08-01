class Account::AppEditorsController < Account::ApplicationController
  layout "editor"
  before_action :set_app

  def show
    @messages = @app.app_chat_messages.order(created_at: :asc)
    @files = @app.app_files.order(:path)
    @selected_file = @files.find_by(id: params[:file_id]) || @files.first

    respond_to do |format|
      format.html
      format.turbo_stream do
        if params[:file_id]
          render turbo_stream: turbo_stream.replace("code_editor",
            partial: "account/app_editors/code_editor",
            locals: {file: @selected_file})
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
    @message = @app.app_chat_messages.build(message_params)
    @message.role = "user"
    @message.user = current_user

    if @message.save
      # Create initial AI response placeholder
      ai_response = @app.app_chat_messages.create!(
        role: "assistant",
        content: "Analyzing your request and planning the changes...",
        status: "planning"
      )

      # Start processing
      ProcessAppUpdateJob.perform_later(@message)

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
              partial: "account/app_editors/chat_form",
              locals: {app: @app}),
            turbo_stream.execute("document.getElementById('chat_container').scrollTop = document.getElementById('chat_container').scrollHeight")
          ]
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("chat_form",
            partial: "account/app_editors/chat_form",
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

  private

  def set_app
    @app = current_team.apps.find(params[:app_id])
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
