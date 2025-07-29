class App < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :creator, class_name: "Membership"
  # 🚅 add belongs_to associations above.

  has_many :app_generations
  has_many :app_files
  has_many :app_versions
  has_many :app_collaborators
  has_many :purchases
  has_many :app_reviews
  has_many :flash_sales
  has_many :app_analytics
  has_many :posts
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  scope :published, -> { where(status: 'published', visibility: 'public') }
  scope :featured, -> { where(featured: true).where('featured_until > ?', Time.current) }
  # 🚅 add scopes above.

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :creator, scope: true
  validates :prompt, presence: true
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  # 🚅 add validations above.

  before_validation :generate_slug
  after_create :create_initial_generation
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_creators
    team.memberships.current_and_invited
  end

  private

  def generate_slug
    self.slug ||= name&.parameterize
  end

  def create_initial_generation
    app_generations.create!(
      prompt: prompt,
      status: 'processing',
      ai_model: 'kimi-k2',
      started_at: Time.current
    )
  end

  # 🚅 add methods above.
end
