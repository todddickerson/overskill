class Account::AppAuditLogsController < Account::ApplicationController
  account_load_and_authorize_resource :app_audit_log, through: :app, through_association: :app_audit_logs

  # GET /account/apps/:app_id/app_audit_logs
  # GET /account/apps/:app_id/app_audit_logs.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_audit_logs/:id
  # GET /account/app_audit_logs/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/apps/:app_id/app_audit_logs/new
  def new
  end

  # GET /account/app_audit_logs/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_audit_logs
  # POST /account/apps/:app_id/app_audit_logs.json
  def create
    respond_to do |format|
      if @app_audit_log.save
        format.html { redirect_to [:account, @app_audit_log], notice: I18n.t("app_audit_logs.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_audit_log] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_audit_log.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_audit_logs/:id
  # PATCH/PUT /account/app_audit_logs/:id.json
  def update
    respond_to do |format|
      if @app_audit_log.update(app_audit_log_params)
        format.html { redirect_to [:account, @app_audit_log], notice: I18n.t("app_audit_logs.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_audit_log] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_audit_log.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_audit_logs/:id
  # DELETE /account/app_audit_logs/:id.json
  def destroy
    @app_audit_log.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_audit_logs], notice: I18n.t("app_audit_logs.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :occurred_at)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
