class Account::AppVersionsController < Account::ApplicationController
  account_load_and_authorize_resource :app_version, through: :app, through_association: :app_versions

  # GET /account/apps/:app_id/app_versions
  # GET /account/apps/:app_id/app_versions.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_versions/:id
  # GET /account/app_versions/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/apps/:app_id/app_versions/new
  def new
  end

  # GET /account/app_versions/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_versions
  # POST /account/apps/:app_id/app_versions.json
  def create
    respond_to do |format|
      if @app_version.save
        format.html { redirect_to [:account, @app_version], notice: I18n.t("app_versions.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_version] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_version.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_versions/:id
  # PATCH/PUT /account/app_versions/:id.json
  def update
    respond_to do |format|
      if @app_version.update(app_version_params)
        format.html { redirect_to [:account, @app_version], notice: I18n.t("app_versions.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_version] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_version.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_versions/:id
  # DELETE /account/app_versions/:id.json
  def destroy
    @app_version.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_versions], notice: I18n.t("app_versions.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :published_at)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
