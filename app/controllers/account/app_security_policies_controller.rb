class Account::AppSecurityPoliciesController < Account::ApplicationController
  account_load_and_authorize_resource :app_security_policy, through: :app, through_association: :app_security_policies

  # GET /account/apps/:app_id/app_security_policies
  # GET /account/apps/:app_id/app_security_policies.json
  def index
    delegate_json_to_api
  end

  # GET /account/app_security_policies/:id
  # GET /account/app_security_policies/:id.json
  def show
    delegate_json_to_api
  end

  # GET /account/apps/:app_id/app_security_policies/new
  def new
  end

  # GET /account/app_security_policies/:id/edit
  def edit
  end

  # POST /account/apps/:app_id/app_security_policies
  # POST /account/apps/:app_id/app_security_policies.json
  def create
    respond_to do |format|
      if @app_security_policy.save
        format.html { redirect_to [:account, @app_security_policy], notice: I18n.t("app_security_policies.notifications.created") }
        format.json { render :show, status: :created, location: [:account, @app_security_policy] }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @app_security_policy.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /account/app_security_policies/:id
  # PATCH/PUT /account/app_security_policies/:id.json
  def update
    respond_to do |format|
      if @app_security_policy.update(app_security_policy_params)
        format.html { redirect_to [:account, @app_security_policy], notice: I18n.t("app_security_policies.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @app_security_policy] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @app_security_policy.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/app_security_policies/:id
  # DELETE /account/app_security_policies/:id.json
  def destroy
    @app_security_policy.destroy
    respond_to do |format|
      format.html { redirect_to [:account, @app, :app_security_policies], notice: I18n.t("app_security_policies.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  if defined?(Api::V1::ApplicationController)
    include strong_parameters_from_api
  end

  def process_params(strong_params)
    assign_date_and_time(strong_params, :last_violation)
    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
