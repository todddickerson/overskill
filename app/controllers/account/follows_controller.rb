class Account::FollowsController < Account::ApplicationController
  account_load_and_authorize_resource :follow, through: :team, through_association: :follows

  # GET /account/teams/:team_id/follows
  # GET /account/teams/:team_id/follows.json
  def index
    delegate_json_to_api
  end

  # GET /account/follows/:id
  # GET /account/follows/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/teams/:team_id/follows/new
  def new
  end

  # GET /account/follows/:id/edit
  def edit
  end

  # POST /account/teams/:team_id/follows
  # POST /account/teams/:team_id/follows.json
  def create
    respond_to do |format|
      if @follow.save
        format.html { redirect_to [:account, @follow], notice: I18n.t("follows.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @follow] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @follow.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/follows/:id
  # PATCH/PUT /account/follows/:id.json
  def update
    respond_to do |format|
      if @follow.update(follow_params)
        format.html { redirect_to [:account, @follow], notice: I18n.t("follows.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @follow] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @follow.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/follows/:id
  # DELETE /account/follows/:id.json
  def destroy
    @follow.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @team, :follows], notice: I18n.t("follows.notifications.destroyed") }
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
