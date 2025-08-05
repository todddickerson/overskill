class AppAuditLog < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :app
  belongs_to :resource_id
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  has_one :team, through: :app
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :action_type, presence: true
  validates :occurred_at, presence: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
