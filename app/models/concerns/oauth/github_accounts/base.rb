module Oauth::GithubAccounts::Base
  extend ActiveSupport::Concern
  # 🚅 add concerns above.

  included do
    belongs_to :user, optional: true
    # 🚅 add belongs_to associations above.

    has_many :webhooks_incoming_oauth_github_account_webhooks, class_name: "Webhooks::Incoming::Oauth::GithubAccountWebhook", foreign_key: "oauth_github_account_id"
    has_many :integrations_github_installations, class_name: "Integrations::GithubInstallation", foreign_key: "oauth_github_account_id"
    # 🚅 add has_many associations above.

    # 🚅 add has_one associations above.

    # 🚅 add scopes above.

    validates :uid, presence: true
    # 🚅 add validations above.

    # 🚅 add callbacks above.

    # 🚅 add delegations above.
  end

  def label_string
    name
  end

  # TODO You should update this with an implementation appropriate for the provider you're integrating with.
  # This must return _something_, otherwise new installations won't save.
  def name
    data.dig("info", "name").presence || "Github Account"
  rescue
    "Github Account"
  end

  def name_was
    name
  end

  def update_from_oauth(auth)
    self.uid = auth.uid
    self.data = auth
    save
  end

  # 🚅 add methods above.
end
