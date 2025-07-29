class CreateFollows < ActiveRecord::Migration[8.0]
  def change
    create_table :follows do |t|
      t.references :team, null: false, foreign_key: true
      t.references :follower, null: false, foreign_key: {to_table: :users}
      t.references :followed, null: false, foreign_key: {to_table: :creator_profiles}

      t.timestamps
    end

    add_index :follows, [:follower_id, :followed_id], unique: true
  end
end
