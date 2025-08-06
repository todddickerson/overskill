class Account::Oauth::GithubAccountsController < Account::ApplicationController
  account_load_and_authorize_resource :github_account, through: :user, through_association: :oauth_github_accounts

  # GET /account/users/:user_id/oauth/github_accounts
  # GET /account/users/:user_id/oauth/github_accounts.json
  def index
    redirect_to [:edit, :account, @user]
  end

  # GET /account/oauth/github_accounts/:id
  # GET /account/oauth/github_accounts/:id.json
  def show
    unless @github_account.integrations_github_installations.any?
      redirect_to [:edit, :account, @user]
    end
  end

  # GET /account/users/:user_id/oauth/github_accounts/new
  def new
  end

  # GET /account/oauth/github_accounts/:id/edit
  def edit
  end

  # PATCH/PUT /account/oauth/github_accounts/:id
  # PATCH/PUT /account/oauth/github_accounts/:id.json
  def update
    respond_to do |format|
      if @github_account.update(github_account_params)
        format.html { redirect_to [:account, @github_account], notice: I18n.t("oauth/github_accounts.notifications.updated") }
        format.json { render :show, status: :ok, location: [:account, @github_account] }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @github_account.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /account/oauth/github_accounts/:id
  # DELETE /account/oauth/github_accounts/:id.json
  def destroy
    @github_account.update(user: nil)
    respond_to do |format|
      format.html { redirect_to [:account, @user, :oauth, :github_accounts], notice: I18n.t("oauth/github_accounts.notifications.destroyed") }
      format.json { head :no_content }
    end
  end

  private

  # Never trust parameters from the scary internet, only allow the white list through.
  def github_account_params
    params.require(:oauth_github_account).permit
    # 🚅 super scaffolding will insert new fields above this line.
    # 🚅 super scaffolding will insert new arrays above this line.

    # 🚅 super scaffolding will insert processing for new fields above this line.
  end
end
