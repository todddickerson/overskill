class AddIsBuiltToAppFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :app_files, :is_built, :boolean
  end
end
