class Account::AppEditorsController < Account::ApplicationController
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
            locals: { file: @selected_file })
        end
      end
    end
  end
  
  def update_file
    @file = @app.app_files.find(params[:file_id])
    
    if @file.update(content: params[:content])
      # Create a version for manual edits
      @app.app_versions.create!(
        version_number: next_version_number(@app),
        changes_summary: "Manual edit: #{@file.path}",
        files_changed: @file.path
      )
      
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("file_#{@file.id}_status", 
              partial: "account/app_editors/file_status", 
              locals: { file: @file, status: "saved" }),
            turbo_stream.replace("preview_frame",
              partial: "account/app_editors/preview_frame",
              locals: { app: @app })
          ]
        end
        format.json { render json: { status: "saved" } }
      end
    else
      format.json { render json: { status: "error", errors: @file.errors } }
    end
  end
  
  def create_message
    @message = @app.app_chat_messages.build(message_params)
    @message.role = "user"
    
    if @message.save
      ProcessAppUpdateJob.perform_later(@message)
      
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("chat_messages", 
              partial: "account/app_editors/chat_message", 
              locals: { message: @message }),
            turbo_stream.replace("chat_form", 
              partial: "account/app_editors/chat_form", 
              locals: { app: @app })
          ]
        end
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