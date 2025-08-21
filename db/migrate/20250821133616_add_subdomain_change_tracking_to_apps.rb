class AddSubdomainChangeTrackingToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :subdomain_changed_at, :datetime
    add_column :apps, :subdomain_change_count, :integer, default: 0, null: false
    
    # Set existing apps to have 0 changes
    App.update_all(subdomain_change_count: 0)
  end
end
