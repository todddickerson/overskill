class AppVersion < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  belongs_to :user, optional: true
  # 🚅 add belongs_to associations above.

  has_many :app_chat_messages, dependent: :nullify
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :user, scope: true, allow_blank: true
  validates :version_number, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    team.apps
  end

  def valid_users
    team.users
  end

  # 🚅 add methods above.
end
