# Job to create database tables for an app after generation
class CreateAppDatabaseJob < ApplicationJob
  queue_as :database_setup

  def perform(app_id)
    app = App.find(app_id)

    Rails.logger.info "[CreateAppDatabaseJob] Setting up database for app #{app.id}: #{app.name}"

    # Initialize schema service
    schema_service = Database::AppSchemaService.new(app)

    # Create default tables based on app content
    schema_service.setup_default_schema!

    # Log results
    Rails.logger.info "[CreateAppDatabaseJob] Created #{app.app_tables.count} tables for app #{app.id}"

    # Broadcast completion
    broadcast_database_ready(app)
  rescue => e
    Rails.logger.error "[CreateAppDatabaseJob] Failed for app #{app_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
    raise # Re-raise to trigger retry
  end

  private

  def broadcast_database_ready(app)
    # Broadcast to the app editor that database is ready
    ActionCable.server.broadcast(
      "app_#{app.id}_updates",
      {
        type: "database_ready",
        message: "Database tables created successfully",
        tables: app.app_tables.pluck(:name)
      }
    )
  end
end
