class AppVersionFile < ApplicationRecord
  belongs_to :app_version
  belongs_to :app_file
  
  validates :content, presence: true
  validates :action, presence: true
  
  # Actions: created, updated, deleted, restored
  enum :action, {
    created: 'create',
    updated: 'update', 
    deleted: 'delete',
    restored: 'restored'
  }
end
