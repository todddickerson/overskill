class RemoveCloudflareWorkerNameFromApps < ActiveRecord::Migration[8.0]
  def change
    # DEPRECATED: cloudflare_worker_name is no longer used with Workers for Platforms (WFP)
    # WFP uses dispatch namespaces and script names instead of individual worker names
    # - Namespaces: overskill-{rails_env}-{deployment_env} (e.g., overskill-development-preview)
    # - Script names: Generated using obfuscated_id for each app
    # See: app/services/deployment/workers_for_platforms_service.rb

    remove_column :apps, :cloudflare_worker_name, :string
  end
end
