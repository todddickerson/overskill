class Ability
  include CanCan::Ability
  include Roles::Permit

  if billing_enabled?
    include Billing::AbilitySupport
  end

  def initialize(user)
    if user.present?

      # permit is a Bullet Train created "magic" method. It parses all the roles in `config/roles.yml` and automatically inserts the appropriate `can` method calls here
      permit user, through: :memberships, parent: :team

      # INDIVIDUAL USER PERMISSIONS.
      can :manage, User, id: user.id
      can :read, User, id: user.collaborating_user_ids
      can :destroy, Membership, user_id: user.id
      can :manage, Invitation, id: user.teams.map(&:invitations).flatten.map(&:id)

      can :create, Team

      # We only allow users to work with the access tokens they've created, e.g. those not created via OAuth2.
      can :manage, Platform::AccessToken, application: {team_id: user.team_ids}, provisioned: true

      if stripe_enabled?
        can [:read, :create, :destroy], Oauth::StripeAccount, user_id: user.id
        can :manage, Integrations::StripeInstallation, team_id: user.team_ids
        can :destroy, Integrations::StripeInstallation, oauth_stripe_account: {user_id: user.id}
      end

      if google_oauth2_enabled?
        can [:read, :create, :destroy], Oauth::GoogleOauth2Account, user_id: user.id
        can :manage, Integrations::GoogleOauth2Installation, team_id: user.team_ids
        can :destroy, Integrations::GoogleOauth2Installation, oauth_google_oauth2_account: {user_id: user.id}
      end
      if github_enabled?
        can [:read, :create, :destroy], Oauth::GithubAccount, user_id: user.id
        can :manage, Integrations::GithubInstallation, team_id: user.team_ids
        can :destroy, Integrations::GithubInstallation, oauth_github_account: {user_id: user.id}
      end
      # 🚅 super scaffolding will insert any new oauth providers above.

      if billing_enabled?
        apply_billing_abilities user
      end

      if user.developer?
        # the following admin abilities were added by super scaffolding.
      end
    end
  end
end
