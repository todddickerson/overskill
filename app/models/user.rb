class User < ApplicationRecord
  include Users::Base
  include Roles::User
  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  # has_many :purchases # TODO: uncomment when Purchase model exists
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id"
  has_many :following, through: :active_follows, source: :followed
  has_many :user_shard_mappings, dependent: :destroy
  has_many :database_shards, through: :user_shard_mappings
  # 🚅 add has_many associations above.

  has_many :oauth_google_oauth2_accounts, class_name: 'Oauth::GoogleOauth2Account' if google_oauth2_enabled?
  has_many :oauth_github_accounts, class_name: 'Oauth::GithubAccount' if github_enabled?
  # 🚅 add oauth providers above.

  # has_one :referral_code # TODO: uncomment when ReferralCode model exists
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # Supabase sync callbacks
  after_create :create_supabase_auth_user
  after_create :create_default_team
  after_update :sync_to_supabase_profile, if: :should_sync_to_supabase?
  
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # Override to auto-generate team name and user details
  def create_default_team
    # Extract username from email or use a default
    username = email.split('@').first
    
    # Auto-fill user details if not provided
    if first_name.blank? || last_name.blank?
      name_parts = username.split(/[._-]/)
      self.first_name = name_parts.first&.capitalize if first_name.blank?
      self.last_name = name_parts.last&.capitalize if last_name.blank? && name_parts.length > 1
      self.last_name ||= 'User' # Fallback if no last name can be extracted
      save(validate: false) # Save without validation to avoid issues
    end
    
    team_name = "#{first_name}'s Workspace"
    
    # This creates a `Membership`, because `User` `has_many :teams, through: :memberships`
    default_team = teams.create!(name: team_name, time_zone: time_zone || 'UTC')
    memberships.find_by(team: default_team).update(user_email: email, role_ids: [Role.admin.id])
    update(current_team: default_team)
  end
  
  # Supabase sync methods
  def should_sync_to_supabase?
    saved_change_to_email? || saved_change_to_first_name? || saved_change_to_last_name?
  end
  
  private
  
  def create_supabase_auth_user
    SupabaseAuthSyncJob.perform_later(self, 'create')
  end
  
  def sync_to_supabase_profile
    SupabaseAuthSyncJob.perform_later(self, 'update')
  end
  
  # 🚅 add methods above.
end
