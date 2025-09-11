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
    rolled_back: 'rolled_back'
  }, prefix: :deployment
  
  # Deployment environments
  validates :environment, inclusion: { in: %w[preview staging production] }
  validates :environment, uniqueness: { 
    scope: :app_id, 
    conditions: -> { where(is_rollback: false, status: ['deployed', 'deploying']) },
    message: 'can only have one active deployment per environment'
  }

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
    create!(
      app: app,
      environment: environment,
      deployment_id: deployment_id,
      deployment_url: url || generate_environment_url(app, environment),
      commit_sha: commit_sha,
      deployed_at: Time.current,
      deployment_metadata: {
        deployed_by: 'GitHub Migration System',
        deployment_type: environment == 'preview' ? 'auto' : 'manual',
        timestamp: Time.current.iso8601,
        app_obfuscated_id: app.obfuscated_id
      }.to_json
    )
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
    worker_name = "overskill-#{app.name.parameterize}-#{app.obfuscated_id}"
    
    case environment
    when 'preview'
      "https://preview-#{worker_name}.overskill.workers.dev"
    when 'staging'
      "https://staging-#{worker_name}.overskill.workers.dev"
    when 'production'
      "https://#{worker_name}.overskill.workers.dev"
    end
  end
end