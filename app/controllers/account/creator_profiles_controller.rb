class Account::CreatorProfilesController < Account::ApplicationController
  account_load_and_authorize_resource :creator_profile, through: :team, through_association: :creator_profiles

  # GET /account/teams/:team_id/creator_profiles
  # GET /account/teams/:team_id/creator_profiles.json
  def index
    delegate_json_to_api
  end

  # GET /account/creator_profiles/:id
  # GET /account/creator_profiles/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/creator_profiles/new
  def new
  end

  # GET /account/creator_profiles/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/creator_profiles
  # POST /account/teams/:team_id/creator_profiles.json
  def create
    respond_to do |format|
      if @creator_profile.save
        format.html { redirect_to [:account, @creator_profile], notice: I18n.t("creator_profiles.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @creator_profile] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @creator_profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/creator_profiles/:id
  # PATCH/PUT /account/creator_profiles/:id.json
  def update
    respond_to do |format|
      if @creator_profile.update(creator_profile_params)
        format.html { redirect_to [:account, @creator_profile], notice: I18n.t("creator_profiles.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @creator_profile] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @creator_profile.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/creator_profiles/:id
  # DELETE /account/creator_profiles/:id.json
  def destroy
    @creator_profile.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :creator_profiles], notice: I18n.t("creator_profiles.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :featured_until)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
