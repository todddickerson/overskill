class Account::AppCollaboratorsController < Account::ApplicationController
  account_load_and_authorize_resource :app_collaborator, through: :app, through_association: :app_collaborators

  # GET /account/apps/:app_id/app_collaborators
  # GET /account/apps/:app_id/app_collaborators.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_collaborators/:id
  # GET /account/app_collaborators/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/apps/:app_id/app_collaborators/new
  def new
  end

  # GET /account/app_collaborators/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_collaborators
  # POST /account/apps/:app_id/app_collaborators.json
  def create
    respond_to do |format|
      if @app_collaborator.save
        format.html { redirect_to [:account, @app_collaborator], notice: I18n.t("app_collaborators.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_collaborator] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_collaborator.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_collaborators/:id
  # PATCH/PUT /account/app_collaborators/:id.json
  def update
    respond_to do |format|
      if @app_collaborator.update(app_collaborator_params)
        format.html { redirect_to [:account, @app_collaborator], notice: I18n.t("app_collaborators.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_collaborator] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_collaborator.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_collaborators/:id
  # DELETE /account/app_collaborators/:id.json
  def destroy
    @app_collaborator.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_collaborators], notice: I18n.t("app_collaborators.notifications.destroyed") }
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
