class Account::AppSettingsController < Account::ApplicationController
  account_load_and_authorize_resource :app_setting, through: :app, through_association: :app_settings

  # GET /account/apps/:app_id/app_settings
  # GET /account/apps/:app_id/app_settings.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_settings/:id
  # GET /account/app_settings/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/apps/:app_id/app_settings/new
  def new
  end

  # GET /account/app_settings/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_settings
  # POST /account/apps/:app_id/app_settings.json
  def create
    respond_to do |format|
      if @app_setting.save
        format.html { redirect_to [:account, @app_setting], notice: I18n.t("app_settings.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_setting] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_setting.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_settings/:id
  # PATCH/PUT /account/app_settings/:id.json
  def update
    respond_to do |format|
      if @app_setting.update(app_setting_params)
        format.html { redirect_to [:account, @app_setting], notice: I18n.t("app_settings.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_setting] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_setting.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_settings/:id
  # DELETE /account/app_settings/:id.json
  def destroy
    @app_setting.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_settings], notice: I18n.t("app_settings.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
