class Account::Oauth::GoogleOauth2AccountsController < Account::ApplicationController
  account_load_and_authorize_resource :google_oauth2_account, through: :user, through_association: :oauth_google_oauth2_accounts

  # GET /account/users/:user_id/oauth/google_oauth2_accounts
  # GET /account/users/:user_id/oauth/google_oauth2_accounts.json
  def index
    redirect_to [:edit, :account, @user]
  end

  # GET /account/oauth/google_oauth2_accounts/:id
  # GET /account/oauth/google_oauth2_accounts/:id.json
  def show
    unless @google_oauth2_account.integrations_google_oauth2_installations.any?
      redirect_to [:edit, :account, @user]
    end
  end

  # GET /account/users/:user_id/oauth/google_oauth2_accounts/new
  def new
  end

  # GET /account/oauth/google_oauth2_accounts/:id/edit
  def edit
  end

  # PATCH/PUT /account/oauth/google_oauth2_accounts/:id
  # PATCH/PUT /account/oauth/google_oauth2_accounts/:id.json
  def update
    respond_to do |format|
      if @google_oauth2_account.update(google_oauth2_account_params)
        format.html { redirect_to [:account, @google_oauth2_account], notice: I18n.t("oauth/google_oauth2_accounts.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @google_oauth2_account] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @google_oauth2_account.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/oauth/google_oauth2_accounts/:id
  # DELETE /account/oauth/google_oauth2_accounts/:id.json
  def destroy
    @google_oauth2_account.update(user: nil)
    respond_to do |format|
      format.html { redirect_to [:account, @user, :oauth, :google_oauth2_accounts], notice: I18n.t("oauth/google_oauth2_accounts.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  # Never trust parameters from the scary internet, only allow the white list through.
  def google_oauth2_account_params
    params.require(:oauth_google_oauth2_account).permit
    # 🚅 super scaffolding will insert new fields above this line.
    # 🚅 super scaffolding will insert new arrays above this line.

    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
