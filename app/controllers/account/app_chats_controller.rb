class Account::AppChatsController < Account::ApplicationController
  before_action :set_app

  def show
    # Show the chat interface for the app
    @messages = @app.app_chat_messages.order(created_at: :asc)
  end

  def create
    @message = @app.app_chat_messages.build(message_params)
    @message.role = "user"

    if @message.save
      # Process the request with AI - always use V3 Optimized orchestrator
      Rails.logger.info "[AppChats] Using V3 Optimized orchestrator for message ##{@message.id}"
      ProcessAppUpdateJobV3.perform_later(@message)

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append("chat_messages", partial: "account/app_chats/message", locals: {message: @message}),
            turbo_stream.replace("chat_form", partial: "account/app_chats/form", locals: {app: @app, message: @app.app_chat_messages.build}),
            # Redirect to editor immediately so user can watch generation progress
            turbo_stream.append("body", html: "<script>window.location.href = '/account/apps/#{@app.to_param}/editor';</script>")
          ]
        end
        format.html { redirect_to account_app_editor_path(@app) }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("chat_form", partial: "account/app_chats/form", locals: {app: @app, message: @message}) }
        format.html { render :show }
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
end
