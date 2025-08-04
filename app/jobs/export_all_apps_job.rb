class ExportAllAppsJob < ApplicationJob
  queue_as :exports
  
  def perform(team, user)
    # Export all apps for a team and email the results
    Rails.logger.info "Starting export for team #{team.id} requested by user #{user.id}"
    
    begin
      # Create a temporary directory for all exports
      export_dir = Rails.root.join('tmp', 'exports', "team_#{team.id}_#{Time.current.to_i}")
      FileUtils.mkdir_p(export_dir)
      
      # Export each app
      exported_files = []
      
      team.apps.includes(:app_tables, :app_files).find_each do |app|
        Rails.logger.info "Exporting app #{app.id} (#{app.name})"
        
        exporter = DataExport::AppExporterService.new(app)
        
        # Export to ZIP for each app
        zip_file = exporter.export_to_zip
        export_path = export_dir.join("#{app.slug}_export.zip")
        FileUtils.mv(zip_file.path, export_path)
        
        exported_files << {
          app_name: app.name,
          app_slug: app.slug,
          file_path: export_path,
          file_size: File.size(export_path)
        }
      end
      
      # Create master ZIP file
      master_zip_path = export_dir.join("#{team.slug}_all_apps_export.zip")
      
      Zip::File.open(master_zip_path, Zip::File::CREATE) do |zipfile|
        # Add each app's export
        exported_files.each do |export|
          zipfile.add(File.basename(export[:file_path]), export[:file_path])
        end
        
        # Add team-level README
        zipfile.get_output_stream("README.md") do |f|
          f.puts generate_team_readme(team, exported_files)
        end
      end
      
      # Upload to cloud storage (future enhancement)
      # For now, we'll just log the location
      Rails.logger.info "Export completed: #{master_zip_path}"
      
      # Send email notification
      TeamMailer.export_completed(team, user, master_zip_path).deliver_later
      
      # Schedule cleanup after 24 hours
      CleanupExportJob.set(wait: 24.hours).perform_later(export_dir.to_s)
      
    rescue => e
      Rails.logger.error "Export failed for team #{team.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Notify user of failure
      TeamMailer.export_failed(team, user, e.message).deliver_later
    end
  end
  
  private
  
  def generate_team_readme(team, exported_files)
    <<~MARKDOWN
      # OverSkill Team Export
      
      ## Team: #{team.name}
      ## Exported: #{Time.current}
      
      This export contains data for all #{exported_files.count} apps in your team.
      
      ### Apps Included:
      
      #{exported_files.map { |f| "- **#{f[:app_name]}** (#{f[:app_slug]}) - #{number_to_human_size(f[:file_size])}" }.join("\n")}
      
      ### What's in Each Export:
      
      Each app export contains:
      - Complete SQL schema and data
      - JSON format data for easy processing
      - All application files
      - Detailed import instructions
      
      ### Data Portability Commitment:
      
      This export demonstrates OverSkill's commitment to data ownership.
      You can import this data into:
      - Your own Supabase instance
      - Any PostgreSQL 14+ database
      - Other platforms that support SQL imports
      
      ### Next Steps:
      
      1. Extract the individual app ZIP files
      2. Choose your target database platform
      3. Follow the import instructions in each app's README
      4. Update your application configurations
      
      ### Support:
      
      Need help? Contact us at support@overskill.dev
      
      Thank you for trusting OverSkill with your applications!
    MARKDOWN
  end
  
  def number_to_human_size(size)
    if size < 1024
      "#{size} B"
    elsif size < 1024 * 1024
      "#{(size / 1024.0).round(2)} KB"
    elsif size < 1024 * 1024 * 1024
      "#{(size / (1024.0 * 1024)).round(2)} MB"
    else
      "#{(size / (1024.0 * 1024 * 1024)).round(2)} GB"
    end
  end
end