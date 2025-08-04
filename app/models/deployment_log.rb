class DeploymentLog < ApplicationRecord
  belongs_to :app
  belongs_to :initiated_by, class_name: "User"
  belongs_to :rollback_from, class_name: "DeploymentLog", optional: true
  
  has_many :build_logs, dependent: :destroy
  
  STATUSES = %w[pending building deploying success failed cancelled].freeze
  ENVIRONMENTS = %w[development staging production].freeze
  
  validates :status, inclusion: { in: STATUSES }
  validates :environment, inclusion: { in: ENVIRONMENTS }
  
  scope :recent, -> { order(created_at: :desc) }
  scope :successful, -> { where(status: 'success') }
  scope :for_environment, ->(env) { where(environment: env) }
  
  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
  
  def duration_in_words
    return "In progress" unless completed_at
    
    seconds = duration
    return nil unless seconds
    
    if seconds < 60
      "#{seconds.round}s"
    elsif seconds < 3600
      "#{(seconds / 60).round}m #{(seconds % 60).round}s"
    else
      "#{(seconds / 3600).round}h #{((seconds % 3600) / 60).round}m"
    end
  end
  
  def can_rollback?
    status == 'success' && 
    environment == 'production' && 
    rollback_from_id.nil? &&
    app.deployment_logs.successful.for_environment(environment).where.not(id: id).exists?
  end
  
  def add_log(level, message)
    build_logs.create!(level: level, message: message)
  end
  
  def mark_as_building!
    update!(status: 'building')
    add_log('info', 'Build started')
  end
  
  def mark_as_deploying!
    update!(status: 'deploying')
    add_log('info', 'Deployment started')
  end
  
  def mark_as_success!(url = nil)
    update!(
      status: 'success',
      completed_at: Time.current,
      deployment_url: url
    )
    add_log('success', 'Deployment completed successfully')
  end
  
  def mark_as_failed!(error_message)
    update!(
      status: 'failed',
      completed_at: Time.current,
      error_message: error_message
    )
    add_log('error', "Deployment failed: #{error_message}")
  end
end
