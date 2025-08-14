class ConsolidateSlugIntoSubdomain < ActiveRecord::Migration[8.0]
  def up
    # First, ensure all apps have subdomain populated from slug
    execute <<-SQL
      UPDATE apps 
      SET subdomain = slug 
      WHERE subdomain IS NULL AND slug IS NOT NULL
    SQL
    
    # For apps where both are different, prefer subdomain (it's the newer field)
    # Log any conflicts for manual review
    conflicts = App.where("subdomain IS NOT NULL AND slug IS NOT NULL AND subdomain != slug")
    if conflicts.any?
      puts "\n⚠️  Found #{conflicts.count} apps with different slug and subdomain values:"
      conflicts.each do |app|
        puts "  App ##{app.id} '#{app.name}': slug='#{app.slug}', subdomain='#{app.subdomain}' (keeping subdomain)"
      end
    end
    
    # Remove the slug index and column
    remove_index :apps, :slug
    remove_column :apps, :slug, :string
    
    # Ensure subdomain is not null (it was already unique)
    change_column_null :apps, :subdomain, false
  end
  
  def down
    # Re-add slug column
    add_column :apps, :slug, :string
    add_index :apps, :slug, unique: true
    
    # Populate slug from subdomain
    execute <<-SQL
      UPDATE apps 
      SET slug = subdomain 
      WHERE subdomain IS NOT NULL
    SQL
    
    # Make slug not null
    change_column_null :apps, :slug, false
    
    # Make subdomain nullable again
    change_column_null :apps, :subdomain, true
  end
end