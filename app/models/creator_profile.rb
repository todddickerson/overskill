class CreatorProfile < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :membership
  # 🚅 add belongs_to associations above.

  has_many :apps, through: :membership
  has_many :posts, through: :membership
  has_many :passive_follows, class_name: "Follow", foreign_key: "followed_id"
  has_many :followers, through: :passive_follows, source: :follower
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  validates :username, presence: true, uniqueness: true
  validates :level, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :membership_id, uniqueness: true
  # 🚅 add validations above.

  before_validation :generate_slug
  # 🚅 add callbacks above.

  delegate :user, to: :membership
  # 🚅 add delegations above.

  private

  def generate_slug
    self.slug ||= username&.parameterize
  end
  # 🚅 add methods above.
end
