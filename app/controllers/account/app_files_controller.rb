class Account::AppFilesController < Account::ApplicationController
  account_load_and_authorize_resource :app_file, through: :team, through_association: :app_files

  # GET /account/teams/:team_id/app_files
  # GET /account/teams/:team_id/app_files.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_files/:id
  # GET /account/app_files/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/app_files/new
  def new
  end

  # GET /account/app_files/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/app_files
  # POST /account/teams/:team_id/app_files.json
  def create
    respond_to do |format|
      if @app_file.save
        format.html { redirect_to [:account, @app_file], notice: I18n.t("app_files.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_file] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_file.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_files/:id
  # PATCH/PUT /account/app_files/:id.json
  def update
    respond_to do |format|
      if @app_file.update(app_file_params)
        format.html { redirect_to [:account, @app_file], notice: I18n.t("app_files.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_file] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_file.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_files/:id
  # DELETE /account/app_files/:id.json
  def destroy
    @app_file.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :app_files], notice: I18n.t("app_files.notifications.destroyed") }
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
