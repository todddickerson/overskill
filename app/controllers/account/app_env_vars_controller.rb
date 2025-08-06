class Account::AppEnvVarsController < Account::ApplicationController
  account_load_and_authorize_resource :app_env_var, through: :app, through_association: :app_env_vars

  # GET /account/apps/:app_id/app_env_vars
  # GET /account/apps/:app_id/app_env_vars.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_env_vars/:id
  # GET /account/app_env_vars/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/apps/:app_id/app_env_vars/new
  def new
  end

  # GET /account/app_env_vars/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_env_vars
  # POST /account/apps/:app_id/app_env_vars.json
  def create
    respond_to do |format|
      if @app_env_var.save
        format.html { redirect_to [:account, @app_env_var], notice: I18n.t("app_env_vars.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_env_var] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_env_var.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_env_vars/:id
  # PATCH/PUT /account/app_env_vars/:id.json
  def update
    respond_to do |format|
      if @app_env_var.update(app_env_var_params)
        format.html { redirect_to [:account, @app_env_var], notice: I18n.t("app_env_vars.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_env_var] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_env_var.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_env_vars/:id
  # DELETE /account/app_env_vars/:id.json
  def destroy
    @app_env_var.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_env_vars], notice: I18n.t("app_env_vars.notifications.destroyed") }
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
