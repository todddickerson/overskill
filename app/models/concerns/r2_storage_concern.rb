# frozen_string_literal: true

module R2StorageConcern
  extend ActiveSupport::Concern
  
  def r2_storage_enabled?
    # Global R2 storage feature flag
    return false unless ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'].present?
    
    # Check for global disable flag
    return false if ENV['DISABLE_R2_STORAGE'] == 'true'
    
    # App-level feature flag (if app exists and has the method)
    if respond_to?(:app) && app.respond_to?(:r2_storage_enabled?)
      return app.r2_storage_enabled?
    end
    
    # Team-level feature flag (if team exists and has setting)
    if respond_to?(:team) && team.respond_to?(:r2_storage_enabled?)
      return team.r2_storage_enabled?
    end
    
    # Default to enabled if R2 is configured
    true
  end
  
  def r2_migration_phase
    # Determine which migration phase we're in
    return :disabled unless r2_storage_enabled?
    
    case ENV['R2_MIGRATION_PHASE']
    when 'testing'
      :testing      # R2 writes enabled, still reading from database
    when 'hybrid'
      :hybrid       # Dual read/write mode
    when 'active'
      :active       # R2 primary, database fallback
    when 'complete'
      :complete     # R2 only (with verification)
    else
      :testing      # Default to testing phase
    end
  end
  
  def should_write_to_r2?
    r2_storage_enabled? && !r2_migration_phase.in?([:disabled])
  end
  
  def should_read_from_r2?
    r2_storage_enabled? && r2_migration_phase.in?([:hybrid, :active, :complete])
  end
  
  def r2_bucket_name
    ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'] || 'overskill-dev'
  end
end