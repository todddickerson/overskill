class AddBadgeVisibilityToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :show_overskill_badge, :boolean, default: true, null: false

    # Set existing apps to show badge by default
    reversible do |dir|
      dir.up do
        App.update_all(show_overskill_badge: true)
      end
    end
  end
end
