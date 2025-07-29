class CreateApps < ActiveRecord::Migration[8.0]
  def change
    create_table :apps do |t|
      t.references :team, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.references :creator, null: false, foreign_key: {to_table: "memberships"}
      t.text :prompt, null: false
      t.string :app_type, default: 'tool'
      t.string :framework, default: 'react'
      t.string :status, default: 'generating'
      t.string :visibility, default: 'private'
      t.integer :base_price, null: false, default: 0
      t.string :stripe_product_id
      t.string :preview_url
      t.string :production_url
      t.string :github_repo
      t.integer :total_users, default: 0
      t.integer :total_revenue, default: 0
      t.integer :rating, default: 0
      t.boolean :featured, default: false
      t.datetime :featured_until
      t.datetime :launch_date
      t.string :ai_model
      t.integer :ai_cost, default: 0

      t.timestamps
    end

    add_index :apps, :slug, unique: true
    add_index :apps, :status
    add_index :apps, :visibility
    add_index :apps, :featured
  end
end
