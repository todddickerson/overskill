class CreateTeamDatabaseConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :team_database_configs do |t|
      t.references :team, null: false, foreign_key: true
      t.string :database_mode, null: false, default: 'managed'
      t.string :supabase_url
      t.text :supabase_service_key
      t.text :supabase_anon_key
      t.string :migration_status
      t.datetime :last_migration_at
      t.json :export_format_preferences, default: {}
      t.text :custom_rls_policies
      t.text :notes
      t.boolean :validated, default: false
      t.datetime :last_validated_at

      t.timestamps
    end
    
    # team_id index is already created by references
    add_index :team_database_configs, :database_mode
  end
end
