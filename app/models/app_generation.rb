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
  validates :status, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    team.apps
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def generating?
    status == "generating"
  end

  # 🚅 add methods above.
end
