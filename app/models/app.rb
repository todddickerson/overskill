class App < ApplicationRecord
  include AutoPreview
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :creator, class_name: "Membership"
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
  # has_many :purchases # TODO: uncomment when Purchase model exists
  # has_many :app_reviews # TODO: uncomment when AppReview model exists
  # has_many :flash_sales # TODO: uncomment when FlashSale model exists
  # has_many :app_analytics # TODO: uncomment when AppAnalytic model exists
  # has_many :posts # TODO: uncomment when Post model exists
  has_many :app_security_policies, dependent: :destroy
  has_many :app_audit_logs, dependent: :destroy
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
    # Return the custom domain if set (future feature), otherwise use the default overskill.app subdomain
    # TODO: Add custom_domain column when implementing entri.com integration
    "https://#{slug}.overskill.app"
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

  private

  def generate_slug
    self.slug ||= name&.parameterize
  end

  # 🚅 add methods above.
end
