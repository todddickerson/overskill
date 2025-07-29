class AppCollaborator < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  belongs_to :membership, optional: true
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :membership, scope: true
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    raise "please review and implement `valid_apps` in `app/models/app_collaborator.rb`."
    # please specify what objects should be considered valid for assigning to `app`.
    # the resulting code should probably look something like `team.apps`.
  end

  def valid_memberships
    raise "please review and implement `valid_memberships` in `app/models/app_collaborator.rb`."
    # please specify what objects should be considered valid for assigning to `membership`.
    # the resulting code should probably look something like `team.memberships`.
  end

  # 🚅 add methods above.
end
