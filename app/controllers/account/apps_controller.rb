class Account::AppsController < Account::ApplicationController
  account_load_and_authorize_resource :app, through: :team, through_association: :apps
  
  # Load app for custom actions that might not be covered by account_load_and_authorize_resource
  before_action :load_app_for_custom_actions, only: [:deploy, :activity_monitor, :deployment_info, :generate_logo, :upload_logo, :debug_error]

  # GET /account/teams/:team_id/apps
  # GET /account/teams/:team_id/apps.json
  def index
    delegate_json_to_api
  end

  # GET /account/apps/:id
  # GET /account/apps/:id.json
  def show
    respond_to do |format|
      format.html { redirect_to account_app_editor_path(@app) }
      format.json { delegate_json_to_api }
    end
  end

  # GET /account/teams/:team_id/apps/new
  def new
  end

  # GET /account/apps/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/apps
  # POST /account/teams/:team_id/apps.json
  def create
    respond_to do |format|
      if @app.save
        # Trigger AI generation if this is a new app
        if @app.prompt.present?
          generation = @app.app_generations.create!(
            team: @app.team,
            prompt: @app.prompt,
            status: "pending",
            started_at: Time.current
          )
          AppGenerationJob.perform_later(generation)
        end

        # Redirect to editor for new apps
        format.html { redirect_to account_app_editor_path(@app), notice: I18n.t("apps.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/apps/:id
  # PATCH/PUT /account/apps/:id.json
  def update
    respond_to do |format|
      if @app.update(app_params)
        format.html { redirect_to [:account, @app], notice: I18n.t("apps.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/apps/:id
  # DELETE /account/apps/:id.json
  def destroy
    @app.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :apps], notice: I18n.t("apps.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  # POST /account/apps/:id/generate_logo
  def generate_logo
    GenerateAppLogoJob.perform_later(@app.id)
    
    respond_to do |format|
      format.json { 
        render json: { 
          success: true, 
          message: "Logo generation started. This may take a few moments..." 
        } 
      }
    end
  rescue => e
    Rails.logger.error "Logo generation error: #{e.message}"
    respond_to do |format|
      format.json { 
        render json: { 
          success: false, 
          error: "Failed to start logo generation" 
        }, status: :unprocessable_entity 
      }
    end
  end

  # POST /account/apps/:id/upload_logo
  def upload_logo
    unless params[:logo].present?
      return render json: { 
        success: false, 
        error: "No logo file provided" 
      }, status: :bad_request
    end

    logo_file = params[:logo]
    
    # Validate file type
    unless logo_file.content_type&.start_with?('image/')
      return render json: { 
        success: false, 
        error: "Please upload an image file" 
      }, status: :bad_request
    end
    
    # Validate file size (5MB max)
    if logo_file.size > 5.megabytes
      return render json: { 
        success: false, 
        error: "File size must be less than 5MB" 
      }, status: :bad_request
    end
    
    # Remove existing logo if present
    @app.logo.purge if @app.logo.attached?
    
    # Attach new logo
    @app.logo.attach(logo_file)
    
    respond_to do |format|
      format.json { 
        render json: { 
          success: true, 
          message: "Logo uploaded successfully!" 
        } 
      }
    end
  rescue => e
    Rails.logger.error "Logo upload error: #{e.message}"
    respond_to do |format|
      format.json { 
        render json: { 
          success: false, 
          error: "Failed to upload logo" 
        }, status: :unprocessable_entity 
      }
    end
  end

  # POST /account/apps/:id/debug_error
  def debug_error
    error_info = params[:error]
    auto_debug = params[:auto_debug]

    unless error_info.present?
      return render json: { 
        success: false, 
        error: "No error information provided" 
      }, status: :bad_request
    end

    # Create AI debugging message
    debug_message = build_debug_message(error_info)
    
    # Create a chat message for the debugging request
    chat_message = @app.app_chat_messages.create!(
      content: debug_message,
      role: 'system',
      auto_debug: auto_debug || false
    )

    # Queue AI response job
    ChatResponseJob.perform_later(chat_message.id)
    
    respond_to do |format|
      format.json { 
        render json: { 
          success: true, 
          message: "AI is analyzing and fixing the error..." 
        } 
      }
    end
  rescue => e
    Rails.logger.error "Error debugging failed: #{e.message}"
    respond_to do |format|
      format.json { 
        render json: { 
          success: false, 
          error: "Failed to start error debugging" 
        }, status: :unprocessable_entity 
      }
    end
  end

  # POST /account/apps/:id/deploy
  def deploy
    Rails.logger.info "[Deploy] Starting deployment for app #{@app.id} with params: #{params.inspect}"
    
    # Check if app has files to deploy
    unless @app.app_files.any?
      Rails.logger.info "[Deploy] App #{@app.id} has no files to deploy"
      render json: { error: "No files to deploy" }, status: :unprocessable_entity
      return
    end

    # Determine deployment target
    environment = params[:environment] || "production"
    Rails.logger.info "[Deploy] Deploying app #{@app.id} to #{environment}"
    
    begin
      # Queue deployment job with environment
      job = DeployAppJob.perform_later(@app.id, environment)
      Rails.logger.info "[Deploy] Successfully queued deployment job #{job.job_id} for app #{@app.id}"

      respond_to do |format|
        format.json { render json: { message: "Deployment started", status: "deploying", environment: environment } }
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("deploy_status",
            html: %Q{<span class="text-yellow-400"><i class="fas fa-spinner fa-spin mr-1"></i>Deploying to #{environment}...</span>})
        end
      end
    rescue => e
      Rails.logger.error "[Deploy] Failed to queue deployment job for app #{@app.id}: #{e.message}"
      Rails.logger.error "[Deploy] Error backtrace: #{e.backtrace.join("\n")}"
      
      render json: { error: "Failed to start deployment: #{e.message}" }, status: :internal_server_error
    end
  end

  # GET /account/apps/:id/activity_monitor
  def activity_monitor
    respond_to do |format|
      format.html { render partial: "account/app_editors/activity_monitor", locals: { app: @app } }
      format.json { redirect_to account_app_api_calls_path(@app) }
    end
  end

  # GET /account/apps/:id/deployment_info
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

  private
  
  def load_app_for_custom_actions
    @app ||= current_team.apps.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "[#{action_name}] App not found with ID: #{params[:id]}"
    render json: { error: "App not found" }, status: :not_found
  end

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :featured_until)
    assign_date_and_time(strong_params, :launch_date)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end

  def build_debug_message(error_info)
    error_type = detect_error_type(error_info)
    
    message = "🔧 **Automatic Error Detection**\n\n"
    message += "I detected a #{error_type} error in your app preview:\n\n"
    message += "**Error Details:**\n"
    message += "```\n#{error_info['message']}\n```\n\n"
    
    if error_info['filename'].present? && error_info['line'].present?
      message += "**Location:** #{error_info['filename']}:#{error_info['line']}\n\n"
    end
    
    message += "**What I'll do:**\n"
    case error_type
    when "Reference Error"
      message += "- Find the undefined variable/component\n"
      message += "- Check for missing imports or declarations\n"
      message += "- Fix the reference or add the missing code\n"
    when "Syntax Error"
      message += "- Locate the syntax issue\n"
      message += "- Fix brackets, semicolons, or other syntax problems\n"
      message += "- Ensure proper JavaScript/React syntax\n"
    when "Type Error"
      message += "- Check for null/undefined property access\n"
      message += "- Add proper null checks or default values\n"
      message += "- Fix type-related issues\n"
    else
      message += "- Analyze the error and identify the root cause\n"
      message += "- Implement the appropriate fix\n"
      message += "- Test to ensure the error is resolved\n"
    end
    
    message += "\nLet me analyze your code and fix this issue..."
    message
  end

  def detect_error_type(error_info)
    message = error_info['message'].to_s.downcase
    
    return "Reference Error" if message.include?("is not defined") || message.include?("referenceerror")
    return "Syntax Error" if message.include?("syntaxerror") || message.include?("unexpected token")
    return "Type Error" if message.include?("cannot read propert") || message.include?("typeerror")
    return "Module Error" if message.include?("module") && message.include?("not found")
    
    "JavaScript Error"
  end
end
