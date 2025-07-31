class ChangeStartedAtToNullableInAppGenerations < ActiveRecord::Migration[8.0]
  def change
    change_column_null :app_generations, :started_at, true
  end
end
