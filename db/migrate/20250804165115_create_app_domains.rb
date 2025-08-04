class CreateAppDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :app_domains do |t|
      t.references :app, null: false, foreign_key: true
      t.string :domain
      t.string :status
      t.datetime :verified_at
      t.string :ssl_status
      t.string :cloudflare_zone_id
      t.string :cloudflare_record_id

      t.timestamps
    end
  end
end
