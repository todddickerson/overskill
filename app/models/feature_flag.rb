class FeatureFlag < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :enabled, inclusion: { in: [true, false] }
  validates :percentage, inclusion: { in: 0..100 }
  
  scope :enabled, -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }
  
  def self.enabled?(flag_name, user_id: nil)
    flag = find_by(name: flag_name)
    return false unless flag&.enabled?
    
    # Percentage-based rollout
    if flag.percentage < 100 && user_id
      hash = Digest::MD5.hexdigest("#{flag_name}:#{user_id}").to_i(16)
      return (hash % 100) < flag.percentage
    end
    
    true
  end
  
  def rollout_percentage
    enabled? ? percentage : 0
  end
  
  def status_summary
    if enabled?
      if percentage == 100
        "Enabled for all users"
      else
        "Enabled for #{percentage}% of users"
      end
    else
      "Disabled"
    end
  end
end
