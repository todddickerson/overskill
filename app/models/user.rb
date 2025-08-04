class User < ApplicationRecord
  include Users::Base
  include Roles::User
  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  # has_many :purchases # TODO: uncomment when Purchase model exists
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id"
  has_many :following, through: :active_follows, source: :followed
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  # has_one :referral_code # TODO: uncomment when ReferralCode model exists
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # Supabase sync callbacks
  after_create :create_supabase_auth_user
  after_update :sync_to_supabase_profile, if: :should_sync_to_supabase?
  
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # Supabase sync methods
  def should_sync_to_supabase?
    saved_change_to_email? || saved_change_to_first_name? || saved_change_to_last_name?
  end
  
  private
  
  def create_supabase_auth_user
    SupabaseAuthSyncJob.perform_later(self, :create)
  end
  
  def sync_to_supabase_profile
    SupabaseAuthSyncJob.perform_later(self, :update)
  end
  
  # 🚅 add methods above.
end
