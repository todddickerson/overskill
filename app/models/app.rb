require 'timeout'

class App < ApplicationRecord
  include AutoPreview
  include TemplateConfig
  # 🚅 add concerns above.
  
  # DEPRECATED FIELDS (January 2025)
  # cloudflare_worker_name: No longer used with Workers for Platforms (WFP)
  #   - WFP uses dispatch namespaces and script names instead of individual workers
  #   - Namespaces: overskill-{rails_env}-{deployment_env} (e.g., overskill-development-preview)
  #   - Script names: Generated using obfuscated_id for each app
  #   - Migration pending to remove this column from database
  #   - See: app/services/deployment/workers_for_platforms_service.rb

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
  has_many :app_deployments, dependent: :destroy
  # 🚅 add has_many associations above.

  has_one_attached :logo
  # 🚅 add has_one associations above.

  scope :published, -> { where(status: "published", visibility: "public") }
  scope :featured, -> { where(featured: true).where("featured_until > ?", Time.current) }
  # 🚅 add scopes above.

  # Repository status enum for GitHub migration
  # Only define enum if the column exists (fixes BulletTrain roles initialization issue)
  if column_names.include?('repository_status')
    enum :repository_status, {
      pending: 'pending',
      creating: 'creating', 
      ready: 'ready',
      failed: 'failed'
    }, prefix: :repository
  end

  validates :name, presence: true
  validates :subdomain, presence: true, uniqueness: true,
    format: { 
      with: /\A[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\z/,
      message: "must be alphanumeric with hyphens, 1-63 characters"
    }
  validates :creator, scope: true
  validates :prompt, presence: true
  validates :base_price, presence: true, numericality: {greater_than_or_equal_to: 0}
  # 🚅 add validations above.

  before_validation :generate_subdomain
  after_create :copy_template_files
  after_create :create_default_env_vars
  after_create :initiate_ai_generation, if: :should_auto_generate?
  after_create :generate_app_name
  after_create_commit :generate_app_logo
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
    # Return production URL if published, otherwise preview URL
    return production_url if production_url.present? && published?
    return preview_url if preview_url.present?
    
    # Fallback to predicted URL based on subdomain
    base_domain = ENV['APP_BASE_DOMAIN'] || 'overskillproject.com'
    "https://#{subdomain}.#{base_domain}" if subdomain.present?
  end
  
  # Check if app can be published to production
  def can_publish?
    status == 'ready' && preview_url.present? && app_files.exists?
  end
  
  # Publish app to production
  def publish_to_production!
    service = Deployment::ProductionDeploymentService.new(self)
    service.deploy_to_production!
  end
  
  # Update subdomain (with uniqueness check and one-change limit)
  def update_subdomain!(new_subdomain)
    # Check if subdomain has already been changed once
    if subdomain_change_count && subdomain_change_count >= 1
      return {success: false, error: "Subdomain can only be changed once. Current subdomain: #{subdomain}"}
    end
    
    # Validate new subdomain format
    unless new_subdomain =~ /\A[a-z0-9][a-z0-9-]*[a-z0-9]\z/
      return {success: false, error: "Invalid subdomain format. Use lowercase letters, numbers, and hyphens only."}
    end
    
    # Check uniqueness
    if App.where(subdomain: new_subdomain).where.not(id: id).exists?
      return {success: false, error: "Subdomain '#{new_subdomain}' is already taken"}
    end
    
    # Update subdomain with tracking
    old_subdomain = subdomain
    self.subdomain = new_subdomain
    self.subdomain_changed_at = Time.current
    self.subdomain_change_count = (subdomain_change_count || 0) + 1
    
    if save
      # If app is deployed, update the deployment
      if status == 'published' || status == 'ready'
        service = Deployment::ProductionDeploymentService.new(self)
        service.update_subdomain(new_subdomain)
      end
      
      Rails.logger.info "[App #{id}] Subdomain changed from '#{old_subdomain}' to '#{new_subdomain}'"
      {success: true, subdomain: new_subdomain, old_subdomain: old_subdomain}
    else
      {success: false, error: errors.full_messages.join(', ')}
    end
  end

  # Regenerate subdomain based on current name.
  # - Ensures uniqueness using same rules as initial generation
  # - If the app is already published and redeploy_if_published is true, uses
  #   production deployment service to migrate to the new subdomain safely
  # - Returns a result hash: {success:, subdomain:, error:}
  def regenerate_subdomain_from_name!(redeploy_if_published: true)
    base = name&.parameterize
    return {success: false, error: "Name is blank"} unless base.present?

    # Sanitize and trim to valid subdomain
    candidate = base.downcase
      .gsub(/[^a-z0-9\-]/, '-')
      .gsub(/-+/, '-')
      .gsub(/^-|-$/, '')
      .slice(0, 63)

    # Ensure uniqueness against other apps
    if App.where(subdomain: candidate).where.not(id: id).exists?
      5.times do
        random_suffix = SecureRandom.alphanumeric(4).downcase
        truncated_base = candidate.slice(0, 58)
        candidate_with_suffix = "#{truncated_base}-#{random_suffix}"
        unless App.where(subdomain: candidate_with_suffix).where.not(id: id).exists?
          candidate = candidate_with_suffix
          break
        end
      end

      if App.where(subdomain: candidate).where.not(id: id).exists?
        timestamp = Time.current.to_i.to_s.last(6)
        random_part = SecureRandom.alphanumeric(3).downcase
        truncated_base = candidate.slice(0, 52)
        candidate = "#{truncated_base}-#{timestamp}#{random_part}"
      end
    end

    # No-op if unchanged
    return {success: true, subdomain: subdomain} if candidate == subdomain

    if published? && redeploy_if_published
      result = update_subdomain!(candidate)
      return result.merge(subdomain: candidate) if result.is_a?(Hash)
      {success: true, subdomain: candidate}
    else
      update!(subdomain: candidate)
      {success: true, subdomain: candidate}
    end
  rescue => e
    {success: false, error: e.message}
  end

  def generate_app_logo
    GenerateAppLogoJob.set(wait: 2.seconds).perform_later(id)
  end

  def generate_app_name
    Rails.logger.info "[App] Generating app name inline for app ##{id}"
    
    # Add a small delay to prevent conflicts with other callbacks
    sleep(0.1) 
    
    begin
      # Use timeout to ensure we don't wait too long
      Timeout.timeout(2) do
        # Skip if app already has a good name (not default/generic)
        if name_generated_at.present?
          Rails.logger.info "[App] Skipping name generation for app #{id} - already generated name: '#{name}'"
          return
        end

        service = Ai::AppNamerService.new(self)
        result = service.generate_name!

        if result[:success]
          update(name_generated_at: Time.current)
          Rails.logger.info "[App] Successfully generated name for app: #{result[:new_name]}"
          
          # Broadcast the updated navigation to refresh the app name
          broadcast_navigation_update
        else
          Rails.logger.error "[App] Failed to generate name for app #{id}: #{result[:error]}"
        end
      end
    rescue Timeout::Error
      Rails.logger.warn "[App] Name generation timed out after 2 seconds for app #{id}"
    rescue => e
      Rails.logger.error "[App] Exception in inline name generation: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end
  end
  
  # Unified AI generation entry point
  # Set skip_job_trigger to true only when the controller will handle job triggering separately
  def initiate_generation!(initial_prompt = nil, skip_job_trigger: false)
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
    
    # Create assistant placeholder message for V5 builder to update
    # This ensures Action Cable has something to broadcast to immediately
    assistant_message = app_chat_messages.create!(
      role: "assistant",
      content: " ",
      user: message.user,
      status: "executing",
      iteration_count: 0,
      loop_messages: [],
      tool_calls: [],
      thinking_status: "Initializing Overskill AI...",
      is_code_generation: false
    )
    
    Rails.logger.info "[App] Created assistant placeholder ##{assistant_message.id} for AI generation"

    # Trigger job unless explicitly told not to (e.g., when controller handles it)
    unless skip_job_trigger
      Rails.logger.info "[App] Triggering V5 orchestrator for message ##{message.id}"
      ProcessAppUpdateJobV4.perform_later(message) # handles all versions
    end
    
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
  
  # Badge and referral system
  def hide_badge!
    update!(show_overskill_badge: false)
  end
  
  def show_badge!
    update!(show_overskill_badge: true)
  end
  
  def remix_url
    base_url = ENV.fetch('BASE_URL', 'https://overskill.app')
    "#{base_url}/remix?template=#{obfuscated_id}"
  end

  def broadcast_navigation_update
    # Broadcast to all users who might be viewing this app's editor
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{id}",
      target: "app_navigation_#{id}",
      partial: "account/app_editors/app_navigation",
      locals: { app: self }
    )
  rescue => e
    Rails.logger.error "[App] Failed to broadcast navigation update: #{e.message}"
  end

  def visitor_count
    # For now, return a simulated count based on app activity
    # This will be replaced with real analytics when Ahoy integration is complete
    # TODO: Implement real analytics
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

  # =============================================================================
  # GITHUB MIGRATION PROJECT - Repository-per-app Architecture Methods
  # =============================================================================

  # Enhanced deployment status (extends existing deployment_status field)
  def deployment_environments
    envs = {}
    envs[:preview] = preview_url if preview_url.present?
    envs[:staging] = staging_url if staging_url.present?
    envs[:production] = production_url if production_url.present?
    envs
  end

  # Check if app is using the new repository-per-app architecture
  def using_repository_mode?
    repository_name.present? && repository_url.present?
  end

  # Check if app was created with the old app_files architecture
  def using_legacy_mode?
    !using_repository_mode? && app_files.exists?
  end

  # Multi-environment deployment workflow methods
  def can_promote_to_staging?
    repository_ready? && preview_url.present? && deployment_status != 'failed'
  end

  def can_promote_to_production?
    staging_deployed_at.present? && staging_url.present? && deployment_status != 'failed'
  end

  # Repository service integration
  def github_repository_service
    @github_repository_service ||= Deployment::GithubRepositoryService.new(self)
  end

  def cloudflare_workers_service
    @cloudflare_workers_service ||= Deployment::CloudflareWorkersBuildService.new(self)
  end

  # Create GitHub repository via forking (ultra-fast 2-3 seconds)
  def create_repository_via_fork!
    result = github_repository_service.create_app_repository_via_fork
    
    if result[:success]
      Rails.logger.info "[App] ✅ Repository created via fork: #{repository_url}"
      
      # NOTE: Cloudflare Worker creation moved to DeployAppJob
      # Worker should only be created after app files are generated
      # This prevents premature worker creation with empty repositories
      
      result
    else
      Rails.logger.error "[App] ❌ Repository creation failed: #{result[:error]}"
      update!(repository_status: 'failed')
      result
    end
  end

  # Promote app from preview to staging environment
  def promote_to_staging!
    return { success: false, error: 'Cannot promote to staging' } unless can_promote_to_staging?
    
    result = cloudflare_workers_service.promote_to_staging
    
    if result[:success]
      update!(
        deployment_status: 'staging_deployed',
        staging_deployed_at: Time.current
      )
      
      # Create deployment record
      app_deployments.create!(
        environment: 'staging',
        deployment_id: result[:deployment_id],
        deployment_url: staging_url,
        deployed_at: Time.current
      )
      
      Rails.logger.info "[App] ✅ Promoted to staging: #{staging_url}"
    end
    
    result
  end

  # Promote app from staging to production environment
  def promote_to_production!
    return { success: false, error: 'Cannot promote to production' } unless can_promote_to_production?
    
    result = cloudflare_workers_service.promote_to_production
    
    if result[:success]
      update!(
        deployment_status: 'production_deployed',
        last_deployed_at: Time.current,
        status: 'published'  # Mark as published when deployed to production
      )
      
      # Create deployment record
      app_deployments.create!(
        environment: 'production',
        deployment_id: result[:deployment_id],
        deployment_url: production_url,
        deployed_at: Time.current
      )
      
      Rails.logger.info "[App] ✅ Promoted to production: #{production_url}"
    end
    
    result
  end

  # Get comprehensive deployment status across all environments
  def get_deployment_status
    if using_repository_mode?
      cloudflare_workers_service.get_deployment_status
    else
      # Legacy mode status
      {
        success: true,
        legacy_mode: true,
        environments: {
          preview: { url: preview_url, status: preview_url.present? ? 'deployed' : 'not_deployed' },
          staging: { url: staging_url, status: staging_deployed_at ? 'deployed' : 'not_deployed' },
          production: { url: production_url, status: deployment_status == 'production_deployed' ? 'deployed' : 'not_deployed' }
        }
      }
    end
  end

  # Generate URLs using privacy-first obfuscated_id approach
  def generate_worker_name
    base_name = name.parameterize
    "overskill-#{base_name}-#{obfuscated_id}"
  end

  def generate_repository_name
    base_name = name.parameterize
    "#{base_name}-#{obfuscated_id}"
  end
  
  # =============================================================================
  # END GITHUB MIGRATION PROJECT METHODS
  # =============================================================================

  # =============================================================================
  # END OF PUBLIC METHODS
  # =============================================================================
  
  private

  def generate_subdomain
    return if subdomain.present?
    
    # Generate from name
    base = name&.parameterize
    return unless base.present?
    
    # Sanitize for subdomain requirements
    candidate = base.downcase
      .gsub(/[^a-z0-9\-]/, '-')
      .gsub(/-+/, '-')
      .gsub(/^-|-$/, '')
      .slice(0, 63)
    
    # Ensure uniqueness - if duplicate, add random suffix
    if App.where(subdomain: candidate).where.not(id: id).exists?
      # Try up to 5 times with random 4-character suffixes
      5.times do
        # Generate random 4-character alphanumeric string
        random_suffix = SecureRandom.alphanumeric(4).downcase
        
        # Truncate base to make room for suffix (max 63 chars total)
        # Leave room for hyphen and 4 character suffix
        truncated_base = candidate.slice(0, 58)
        
        # Create candidate with random suffix
        candidate_with_suffix = "#{truncated_base}-#{random_suffix}"
        
        unless App.where(subdomain: candidate_with_suffix).where.not(id: id).exists?
          candidate = candidate_with_suffix
          break
        end
      end
      
      # If still not unique after 5 attempts, use timestamp + random for guaranteed uniqueness
      if App.where(subdomain: candidate).where.not(id: id).exists?
        timestamp = Time.current.to_i.to_s.last(6) # Last 6 digits of timestamp
        random_part = SecureRandom.alphanumeric(3).downcase
        truncated_base = candidate.slice(0, 52) # Room for timestamp and random
        candidate = "#{truncated_base}-#{timestamp}#{random_part}"
      end
    end
    
    self.subdomain = candidate
  end

  def copy_template_files
    template_dir = current_template_path
    
    unless Dir.exist?(template_dir)
      Rails.logger.warn "[App] Template directory not found: #{template_dir}"
      return
    end
    
    files_copied = 0
    
    Dir.glob(::File.join(template_dir, "**/*")).each do |file_path|
      next unless ::File.file?(file_path)
      
      relative_path = file_path.sub("#{template_dir}/", '')
      content = ::File.read(file_path)
      
      # Skip empty files
      next if content.blank?
      
      # Create AppFile for each template file
      app_files.create!(
        path: relative_path,
        content: content,
        team: team,
        file_type: determine_app_file_type(relative_path)
      )
      
      files_copied += 1
    end
    
    Rails.logger.info "[App] Copied #{files_copied} template files from #{current_template_version} for app ##{id}"
    
    # Also track which template version was used
    update_column(:template_version_used, current_template_version) if respond_to?(:template_version_used)
  rescue => e
    Rails.logger.error "[App] Failed to copy template files: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
  
  def determine_app_file_type(path)
    case ::File.extname(path).downcase
    when '.tsx', '.ts' then 'typescript'
    when '.jsx', '.js' then 'javascript'
    when '.css' then 'css'
    when '.html' then 'html'
    when '.json' then 'json'
    when '.md' then 'markdown'
    when '.yml', '.yaml' then 'yaml'
    when '.svg' then 'svg'
    when '.png', '.jpg', '.jpeg', '.gif' then 'image'
    else 'text'
    end
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
    initiate_generation!  # Default behavior is to trigger job
  end
  
  # 🚅 add methods above.
end
