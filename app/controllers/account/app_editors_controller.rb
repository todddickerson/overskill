class Account::AppEditorsController < Account::ApplicationController
  layout "editor"
  before_action :set_app

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
        # Only stream updates for actual Turbo Frame interactions that target the code editor
        if turbo_frame_request? && params[:file_id]
          render turbo_stream: turbo_stream.replace(
            "code_editor",
            partial: "account/app_editors/code_editor",
            locals: { file: @selected_file, app: @app }
          )
        else
          # Fallback: serve the full HTML page so Turbo performs a normal visit
          render :show, formats: [:html]
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
      
      # Create a version for manual edits with file snapshot
      @app.app_versions.create!(
        team: @app.team,
        user: current_user,
        version_number: next_version_number(@app),
        changelog: "Manual edit: #{@file.path}",
        changed_files: @file.path,
        files_snapshot: @app.app_files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json
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

  # POST /account/apps/:app_id/editor/messages
  # Creates a new chat message and queues AI processing
  def create_message
    # Build and save the user's message
    @message = build_user_message
    
    if @message.save
      # Queue AI processing of the message
      queue_ai_processing(@message)
      
      # Reset the chat form (messages appear via ActionCable broadcasts)
      render_chat_form_reset
    else
      # Re-render form with errors
      render_chat_form_with_errors
    end
  end
  
  private
  
  # Build a new user message from params
  def build_user_message
    message = @app.app_chat_messages.build(message_params)
    message.role = "user"
    message.user = current_user
    message
  end
  
  # Queue the appropriate AI processing job
  def queue_ai_processing(message)
    # Use the App model's unified method which handles all the logic
    # for determining which AI system to use (V3, Unified, or Legacy)
    Rails.logger.info "[AI] Delegating to App model for message ##{message.id}"
    @app.initiate_generation!
  end
  
  # Render the chat form reset (successful message creation)
  def render_chat_form_reset
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "chat_form",
          partial: "account/app_editors/chat_input_wrapper",
          locals: { app: @app }
        )
      end
    end
  end
  
  # Render the chat form with errors
  def render_chat_form_with_errors
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "chat_form",
          partial: "account/app_editors/chat_input_wrapper",
          locals: { app: @app, message: @message }
        )
      end
    end
  end


  
  def versions
    @versions = @app.app_versions.order(created_at: :desc)
    render partial: "version_history_list", locals: { app: @app, versions: @versions }
  end
  

  def update_preview
    # Trigger preview update (already handled by UpdatePreviewJob)
    UpdatePreviewJob.perform_later(@app.id)
    render json: { success: true }
  end

  def restore_version
    version = @app.app_versions.find(params[:version_id])
    
    begin
      # Restore files from version snapshot
      files_data = JSON.parse(version.files_snapshot)
      
      files_data.each do |file_data|
        file = @app.app_files.find_or_initialize_by(path: file_data['path'])
        file.team = @app.team if file.new_record?
        file.content = file_data['content']
        file.file_type = file_data['file_type']
        file.size_bytes = file_data['content'].bytesize
        file.save!
      end
      
      # Create a new version for the restore action
      restore_version = @app.app_versions.create!(
        team: @app.team,
        user: current_user,
        version_number: next_version_number(@app),
        changelog: "Restored from version #{version.version_number}",
        files_snapshot: version.files_snapshot
      )
      
      # Update preview
      UpdatePreviewJob.perform_later(@app.id)
      
      render json: { success: true, message: "Successfully restored to version #{version.version_number}" }
    rescue => e
      Rails.logger.error "Version restore failed: #{e.message}"
      render json: { success: false, error: e.message }
    end
  end

  def bookmark_version
    version = @app.app_versions.find(params[:version_id])
    version.update!(bookmarked: !version.bookmarked)
    
    render json: { 
      success: true, 
      bookmarked: version.bookmarked,
      message: version.bookmarked? ? "Version bookmarked" : "Bookmark removed"
    }
  end

  def compare_version
    version = @app.app_versions.find(params[:version_id])
    
    # For now, redirect to a comparison view (could be enhanced)
    redirect_to account_app_path(@app, version: version.id)
  end

  private

  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  # Generate the next version number for an app
  def next_version_number(app)
    last_version = app.app_versions.order(created_at: :desc).first
    if last_version
      # Increment patch version (1.0.0 -> 1.0.1)
      parts = last_version.version_number.split(".").map(&:to_i)
      parts[2] = (parts[2] || 0) + 1
      parts.join(".")
    else
      "1.0.0"
    end
  end

  def message_params
    content = params.require(:app_chat_message)[:content] || params.require(:app_chat_message)[:content_mobile]
    { content: content }
  end
end
