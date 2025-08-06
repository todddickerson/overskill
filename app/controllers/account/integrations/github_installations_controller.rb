class Account::Integrations::GithubInstallationsController < Account::ApplicationController
  account_load_and_authorize_resource :github_installation, through: :team, through_association: :integrations_github_installations

  # GET /account/teams/:team_id/integrations/github_installations
  # GET /account/teams/:team_id/integrations/github_installations.json
  def index
    # if you only want these objects shown on their parent's show page, uncomment this:
    # redirect_to [:account, @team]
  end

  # GET /account/integrations/github_installations/:id
  # GET /account/integrations/github_installations/:id.json
  def show
  end

  # GET /account/teams/:team_id/integrations/github_installations/new
  def new
  end

  # GET /account/integrations/github_installations/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/integrations/github_installations
  # POST /account/teams/:team_id/integrations/github_installations.json
  def create
    respond_to do |format|
      if @github_installation.save
        format.html { redirect_to [:account, @team, :integrations_github_installations], notice: I18n.t("integrations/github_installations.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @github_installation] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @github_installation.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/integrations/github_installations/:id
  # PATCH/PUT /account/integrations/github_installations/:id.json
  def update
    respond_to do |format|
      if @github_installation.update(github_installation_params)
        format.html { redirect_to [:account, @github_installation], notice: I18n.t("integrations/github_installations.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @github_installation] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @github_installation.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/integrations/github_installations/:id
  # DELETE /account/integrations/github_installations/:id.json
  def destroy
    @github_installation.destroy
    respond_to do |format|
      format.html { redirect_to params[:return_to] || [:account, @team, :integrations_github_installations], notice: I18n.t("integrations/github_installations.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  # Never trust parameters from the scary internet, only allow the white list through.
  def github_installation_params
    strong_params = params.require(:integrations_github_installation).permit(
      :name,
      # 🚅 super scaffolding will insert new fields above this line.
      multiple_button_values: [],
      multiple_super_select_values: [],
      # 🚅 super scaffolding will insert new arrays above this line.
    )

    assign_checkboxes(strong_params, :multiple_button_values)
    assign_select_options(strong_params, :multiple_super_select_values)
    # 🚅 super scaffolding will insert processing for new fields above this line.

    strong_params
  end
end
