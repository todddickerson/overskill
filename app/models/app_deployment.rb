# AppDeployment Model - Tracks multi-environment deployments
# Supports GitHub Migration Project's deployment workflow:
# Preview (auto) → Staging (manual) → Production (manual)

class AppDeployment < ApplicationRecord
  belongs_to :app

  # Deployment environments
  validates :environment, inclusion: { in: %w[preview staging production] }
  validates :environment, uniqueness: { 
    scope: :app_id, 
    conditions: -> { where(is_rollback: false) },
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
    worker_name = "overskill-#{(app.slug.presence || app.name).parameterize}-#{app.obfuscated_id}"
    
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