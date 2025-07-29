class AppGeneration < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :prompt, presence: true
  validates :started_at, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    raise "please review and implement `valid_apps` in `app/models/app_generation.rb`."
    # please specify what objects should be considered valid for assigning to `app`.
    # the resulting code should probably look something like `team.apps`.
  end

  # 🚅 add methods above.
end
