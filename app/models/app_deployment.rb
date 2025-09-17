# AppDeployment Model - Tracks multi-environment deployments with full state tracking
# Supports GitHub Migration Project's deployment workflow:
# Preview (auto) → Staging (manual) → Production (manual)
#
# Rails Best Practice: Database as source of truth for all deployment state

class AppDeployment < ApplicationRecord
  belongs_to :app

  # Deployment status enum - track every stage
  enum :status, {
    pending: 'pending',
    building: 'building',
    deploying: 'deploying',
    deployed: 'deployed',
    failed: 'failed',
    rolled_back: 'rolled_back',
    superseded: 'superseded'  # Previous deployment replaced by newer one
  }, prefix: :deployment
  
  # Deployment environments
  validates :environment, inclusion: { in: %w[preview staging production] }
  # Note: Uniqueness enforced by application logic in create_for_environment!
  # validate :only_one_active_deployment_per_environment  # Temporarily disabled

  # Scopes for different environments
  scope :preview, -> { where(environment: 'preview') }
  scope :staging, -> { where(environment: 'staging') }
  scope :production, -> { where(environment: 'production') }
  scope :active, -> { where(is_rollback: false) }
  scope :rollbacks, -> { where(is_rollback: true) }

  # Order by deployment time
  scope :recent, -> { order(deployed_at: :desc) }
  scope :chronological, -> { order(deployed_at: :asc) }
  scope :successful, -> { where(status: 'deployed') }
  scope :failed, -> { where(status: 'failed') }
  scope :in_progress, -> { where(status: ['building', 'deploying']) }
  
  # Callbacks to calculate durations automatically
  before_save :calculate_durations
  
  def rollback?
    is_rollback
  end

  def active_deployment?
    !is_rollback
  end

  def preview_deployment?
    environment == 'preview'
  end

  def staging_deployment?
    environment == 'staging'
  end

  def production_deployment?
    environment == 'production'
  end
  
  # State transition helpers with timing
  def start_build!
    update!(
      status: 'building',
      build_started_at: Time.current
    )
  end
  
  def complete_build!
    update!(
      build_completed_at: Time.current,
      status: 'deploying',
      deploy_started_at: Time.current
    )
  end
  
  def complete_deployment!(url = nil)
    update!(
      status: 'deployed',
      deploy_completed_at: Time.current,
      deployment_url: url || deployment_url,
      deployed_at: Time.current
    )
  end
  
  def fail_deployment!(error_message, error_details = nil)
    update!(
      status: 'failed',
      error_message: error_message,
      error_details: error_details,
      deploy_completed_at: Time.current
    )
  end
  
  # Track bundle size and file count
  def track_build_metrics(bundle_size_bytes, files_count)
    update!(
      bundle_size_bytes: bundle_size_bytes,
      files_count: files_count
    )
  end
  
  private

  def only_one_active_deployment_per_environment
    return if is_rollback? # Rollbacks don't count toward active limit
    return unless ['deployed', 'deploying'].include?(status) # Only validate active statuses

    # Skip validation during superseding process
    return if Thread.current[:superseding_deployments]

    existing_active = AppDeployment.where(
      app: app,
      environment: environment,
      is_rollback: false,
      status: ['deployed', 'deploying']
    ).where.not(id: id) # Exclude self for updates

    if existing_active.exists?
      errors.add(:environment, 'can only have one active deployment per environment')
    end
  end

  def calculate_durations
    if build_started_at && build_completed_at
      self.build_duration_seconds = (build_completed_at - build_started_at).to_i
    end
    
    if deploy_started_at && deploy_completed_at
      self.deploy_duration_seconds = (deploy_completed_at - deploy_started_at).to_i
    end
  end

  # Generate deployment metadata for tracking
  def self.create_for_environment!(app:, environment:, deployment_id:, url: nil, commit_sha: nil)
    transaction do
      # Set thread-local flag to skip validation during superseding
      Thread.current[:superseding_deployments] = true

      # Mark any existing active deployments as superseded before creating new one
      AppDeployment.where(
        app: app,
        environment: environment,
        is_rollback: false,
        status: ['deployed', 'deploying']
      ).update_all(status: 'superseded')

      result = create!(
        app: app,
        environment: environment,
        deployment_id: deployment_id,
        deployment_url: url || generate_environment_url(app, environment),
        commit_sha: commit_sha,
        status: 'deployed',  # Explicitly set status since this is called after successful deployment
        deployed_at: Time.current,
        deployment_metadata: {
          deployed_by: 'GitHub Migration System',
          deployment_type: environment == 'preview' ? 'auto' : 'manual',
          timestamp: Time.current.iso8601,
          app_obfuscated_id: app.obfuscated_id
        }.to_json
      )

      # Clear thread-local flag
      Thread.current[:superseding_deployments] = false

      result
    end
  end

  # Generate rollback deployment record
  def self.create_rollback!(app:, environment:, rollback_to_deployment:, deployment_id:)
    create!(
      app: app,
      environment: environment,
      deployment_id: deployment_id,
      deployment_url: rollback_to_deployment.deployment_url,
      commit_sha: rollback_to_deployment.commit_sha,
      deployed_at: Time.current,
      is_rollback: true,
      rollback_version_id: rollback_to_deployment.id.to_s,
      deployment_metadata: {
        rollback_to: rollback_to_deployment.id,
        rollback_from_commit: rollback_to_deployment.commit_sha,
        deployed_by: 'GitHub Migration System',
        deployment_type: 'rollback',
        timestamp: Time.current.iso8601,
        app_obfuscated_id: app.obfuscated_id
      }.to_json
    )
  end

  private

  def self.generate_environment_url(app, environment)
    # Use WFP_APPS_DOMAIN if configured, otherwise fall back to workers.dev
    domain = ENV['WFP_APPS_DOMAIN'] || 'overskill.app'

    # For WFP dispatch, we use obfuscated_id as the script name
    script_name = app.obfuscated_id.downcase

    case environment
    when 'preview'
      "https://preview-#{script_name}.#{domain}"
    when 'staging'
      "https://staging-#{script_name}.#{domain}"
    when 'production'
      # Production uses subdomain directly (no prefix)
      subdomain = app.subdomain || script_name
      "https://#{subdomain}.#{domain}"
    end
  end
end