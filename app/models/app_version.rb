class AppVersion < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  belongs_to :user, optional: true
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :user, scope: true
  validates :version_number, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    raise "please review and implement `valid_apps` in `app/models/app_version.rb`."
    # please specify what objects should be considered valid for assigning to `app`.
    # the resulting code should probably look something like `team.apps`.
  end

  def valid_users
    raise "please review and implement `valid_users` in `app/models/app_version.rb`."
    # please specify what objects should be considered valid for assigning to `user`.
    # the resulting code should probably look something like `team.users`.
  end

  # 🚅 add methods above.
end
