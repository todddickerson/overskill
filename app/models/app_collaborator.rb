class AppCollaborator < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  belongs_to :membership, optional: true
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  has_one :team, through: :app
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :membership, scope: true
  validates :role, inclusion: {in: %w[owner editor viewer]}
  validates :membership, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    team.apps
  end

  def valid_memberships
    team.memberships
  end

  # 🚅 add methods above.
end
