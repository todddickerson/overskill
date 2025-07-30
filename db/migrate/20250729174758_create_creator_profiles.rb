class CreateCreatorProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :creator_profiles do |t|
      t.references :team, null: false, foreign_key: true
      t.references :membership, null: false, foreign_key: true
      t.string :username, null: false
      t.text :bio
      t.integer :level, default: 1, null: false
      t.integer :total_earnings, default: 0
      t.integer :total_sales, default: 0
      t.string :verification_status, default: "unverified"
      t.datetime :featured_until
      t.string :slug, null: false
      t.string :stripe_account_id
      t.string :public_email
      t.string :website_url
      t.string :twitter_handle
      t.string :github_username

      t.timestamps
    end

    add_index :creator_profiles, :username, unique: true
    add_index :creator_profiles, :slug, unique: true
  end
end
