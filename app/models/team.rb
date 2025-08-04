class Team < ApplicationRecord
  include Teams::Base
  include Webhooks::Outgoing::TeamSupport
  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  has_many :creator_profiles, dependent: :destroy
  has_many :follows, dependent: :destroy
  has_many :apps, dependent: :destroy
  has_many :app_generations, dependent: :destroy
  has_many :app_files, dependent: :destroy
  has_many :app_versions, dependent: :destroy
  has_many :app_collaborators, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  has_one :team_database_config, dependent: :destroy
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # Get or create database config with defaults
  def database_config
    team_database_config || create_team_database_config!
  end
  
  # 🚅 add methods above.
end
