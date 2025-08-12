class AddNameGeneratedAtToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :name_generated_at, :datetime
  end
end
