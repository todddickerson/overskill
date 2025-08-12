class AddTokenTrackingToAppVersions < ActiveRecord::Migration[7.0]
  def change
    add_column :app_versions, :ai_tokens_input, :integer, default: 0
    add_column :app_versions, :ai_tokens_output, :integer, default: 0
    add_column :app_versions, :ai_cost_cents, :integer, default: 0
    add_column :app_versions, :ai_model_used, :string
    
    add_index :app_versions, :ai_model_used
    add_index :app_versions, :ai_cost_cents
  end
end