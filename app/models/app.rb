class App < ApplicationRecord
  include AutoPreview
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :creator, class_name: "Membership"
  belongs_to :database_shard, optional: true
  # 🚅 add belongs_to associations above.

  has_many :app_versions, dependent: :destroy
  has_many :app_files, dependent: :destroy
  has_many :app_generations, dependent: :destroy
  has_many :app_collaborators, dependent: :destroy
  has_many :app_chat_messages, dependent: :destroy
  has_many :app_tables, dependent: :destroy
  has_many :app_oauth_providers, dependent: :destroy
  has_many :app_api_integrations, dependent: :destroy
  has_many :deployment_logs, dependent: :destroy
  has_many :app_settings, dependent: :destroy
  has_many :app_api_calls, dependent: :destroy
  has_one :app_auth_setting, dependent: :destroy
  # has_many :purchases # TODO: uncomment when Purchase model exists
  # has_many :app_reviews # TODO: uncomment when AppReview model exists
  # has_many :flash_sales # TODO: uncomment when FlashSale model exists
  # has_many :app_analytics # TODO: uncomment when AppAnalytic model exists
  # has_many :posts # TODO: uncomment when Post model exists
  has_many :app_security_policies, dependent: :destroy
  has_many :app_audit_logs, dependent: :destroy
  has_many :app_env_vars, dependent: :destroy
  # 🚅 add has_many associations above.

  has_one_attached :logo
  # 🚅 add has_one associations above.

  scope :published, -> { where(status: "published", visibility: "public") }
  scope :featured, -> { where(featured: true).where("featured_until > ?", Time.current) }
  # 🚅 add scopes above.

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :creator, scope: true
  validates :prompt, presence: true
  validates :base_price, presence: true, numericality: {greater_than_or_equal_to: 0}
  # 🚅 add validations above.

  before_validation :generate_slug
  after_create :create_default_env_vars
  after_create :initiate_ai_generation, if: :should_auto_generate?
  after_create :generate_app_logo
  # 🚅 add callbacks above.

  # Delegate to team's database config for hybrid architecture
  delegate :database_config, to: :team, prefix: true, allow_nil: true
  # 🚅 add delegations above.

  def valid_creators
    team.memberships.current_and_invited
  end

  def generated?
    status == "generated"
  end

  def generating?
    status == "generating"
  end

  def failed?
    status == "failed"
  end
  
  def published?
    status == "published"
  end

  def published_url
    # Return the actual deployment URL if deployed, otherwise use the predicted subdomain
    return deployment_url if deployment_url.present?
    
    # Generate the subdomain the same way the deployment service does
    subdomain = name.downcase.gsub(/[^a-z0-9\-]/, '-').gsub(/-+/, '-').gsub(/^-|-$/, '')
    subdomain = "app-#{id}" if subdomain.blank?
    
    "https://#{subdomain}.overskill.app"
  end

  def generate_app_logo
    GenerateAppLogoJob.perform_later(id)
  end

  def visitor_count
    # For now, return a simulated count based on app activity
    # This will be replaced with real analytics when Ahoy integration is complete
    base_count = (created_at.to_i / 1000) % 1000
    activity_multiplier = [app_versions.count * 5, app_chat_messages.count * 2].sum
    [base_count + activity_multiplier, 0].max
  end

  def daily_visitors
    # Simulate daily visitor data for the past 7 days
    (0..6).map do |days_ago|
      date = days_ago.days.ago.to_date
      base = visitor_count / 30 # Average daily visitors
      variation = (date.to_time.to_i % 10) - 5 # Add some realistic variation
      [base + variation, 0].max
    end.reverse
  end

  def last_deployed_at
    # Return the most recent deployment timestamp
    [deployed_at, staging_deployed_at].compact.max
  end

  def deployment_status
    # Return deployment status based on app state
    return 'deployed' if status == 'published' && last_deployed_at.present?
    return 'deploying' if status == 'generating'
    return 'failed' if status == 'failed'
    'pending'
  end

  # Get all environment variables for deployment
  def env_vars_for_deployment
    vars = {}
    app_env_vars.each do |env_var|
      vars[env_var.key] = env_var.value
    end
    vars
  end

  # Get environment variables available to AI (non-secret)
  def env_vars_for_ai
    app_env_vars.select(&:available_for_ai?).map do |env_var|
      { key: env_var.key, description: env_var.description }
    end
  end

  # Unified AI generation entry point
  def initiate_generation!(initial_prompt = nil)
    Rails.logger.info "[App] Initiating AI generation for app ##{id}"
    
    # Update prompt if provided
    update!(prompt: initial_prompt) if initial_prompt.present?
    
    # Create initial user message if needed
    message = if app_chat_messages.empty? && prompt.present?
      app_chat_messages.create!(
        role: "user",
        content: prompt,  # Raw prompt - let AI service enhance as needed
        user: creator.user
      )
    else
      app_chat_messages.last
    end
    
    # Default prompt if none provided
    if prompt.blank? && message.content.blank?
      default_prompt = "Generate a simple app with a home page and about page"
      update!(prompt: default_prompt)
      message.update!(content: default_prompt) if message.persisted?
    end

    # Always use V4 orchestrator (Vite + TypeScript + template-based)
    Rails.logger.info "[App] Using V4 orchestrator for app ##{id}"
    ProcessAppUpdateJobV4.perform_later(message)
    
    # Update status
    update!(status: "generating") unless generating?
  end
  
  
  # AI Model selection for A/B testing
  AI_MODELS = {
    'gpt-5' => 'GPT-5 (Fast & Efficient)',
    'claude-sonnet-4' => 'Claude Sonnet 4 (Advanced Reasoning)'
  }.freeze
  
  def ai_model_name
    AI_MODELS[ai_model] || AI_MODELS['gpt-5']
  end
  
  def using_claude?
    ai_model == 'claude-sonnet-4'
  end
  
  def using_gpt5?
    ai_model == 'gpt-5' || ai_model.nil?
  end

  private

  def generate_slug
    self.slug ||= name&.parameterize
  end

  def create_default_env_vars
    AppEnvVar.create_defaults_for_app(self)
  end
  
  def should_auto_generate?
    # Auto-generate if:
    # 1. Prompt is present
    # 2. Status is not already generating/generated/failed
    # 3. No existing chat messages (new app)
    prompt.present? && 
    status.in?(['draft', 'pending', nil]) && 
    app_chat_messages.empty?
  end
  
  def initiate_ai_generation
    Rails.logger.info "[App] Auto-initiating generation for new app ##{id}"
    initiate_generation!
  end
  
  # 🚅 add methods above.
end
