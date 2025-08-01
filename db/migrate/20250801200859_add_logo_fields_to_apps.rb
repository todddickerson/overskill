class AddLogoFieldsToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :logo_prompt, :text
    add_column :apps, :logo_generated_at, :datetime
  end
end
