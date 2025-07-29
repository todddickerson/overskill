class User < ApplicationRecord
  include Users::Base
  include Roles::User
  # 🚅 add concerns above.

  # 🚅 add belongs_to associations above.

  has_many :purchases
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id"
  has_many :following, through: :active_follows, source: :followed
  # 🚅 add has_many associations above.

  # 🚅 add oauth providers above.

  has_one :referral_code
  # 🚅 add has_one associations above.

  # 🚅 add scopes above.

  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # 🚅 add methods above.
end
