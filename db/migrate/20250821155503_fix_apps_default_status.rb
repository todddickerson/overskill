class FixAppsDefaultStatus < ActiveRecord::Migration[8.0]
  def change
    # Fix default status from 'generating' to 'draft' to allow auto-generation to trigger
    # The 'generating' default was preventing should_auto_generate? from working
    # because it checks for status in ['draft', 'pending', nil]
    change_column_default :apps, :status, from: 'generating', to: 'draft'
  end
end
