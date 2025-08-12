class AddSubdomainToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :subdomain, :string
    add_column :apps, :last_deployed_at, :datetime
    add_column :apps, :published_at, :datetime
    
    add_index :apps, :subdomain, unique: true
    
    # Populate subdomain from existing slug for existing apps
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE apps 
          SET subdomain = slug 
          WHERE subdomain IS NULL AND slug IS NOT NULL
        SQL
      end
    end
  end
end
