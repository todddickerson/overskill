namespace :app_versions do
  desc "Backfill missing app_version_files for existing versions"
  task backfill_version_files: :environment do
    puts "Backfilling missing app version file snapshots..."

    # Find app versions without version files
    versions_without_files = AppVersion.joins(:app)
      .left_joins(:app_version_files)
      .where(app_version_files: {id: nil})
      .includes(app: :app_files)

    puts "Found #{versions_without_files.count} versions without file snapshots"

    versions_without_files.each do |version|
      puts "Creating snapshots for version #{version.version_number} of app #{version.app.name}"

      # Create snapshots for all current files in the app
      version.app.app_files.each do |app_file|
        version.app_version_files.create!(
          app_file: app_file,
          content: app_file.content,
          action: "update" # Default action for backfilled snapshots
        )
      end

      puts "  Created #{version.app.app_files.count} file snapshots"
    end

    puts "Backfill complete!"
  end
end
