class Account::AppsController < Account::ApplicationController
  account_load_and_authorize_resource :app, through: :team, through_association: :apps

  # GET /account/teams/:team_id/apps
  # GET /account/teams/:team_id/apps.json
  def index
    delegate_json_to_api
  end

  # GET /account/apps/:id
  # GET /account/apps/:id.json
  def show
    delegate_json_to_api
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
        format.html { redirect_to [:account, @app], notice: I18n.t("apps.notifications.created") }
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

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :featured_until)
    assign_date_and_time(strong_params, :launch_date)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
