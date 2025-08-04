class AppTable < ApplicationRecord
  belongs_to :app
  has_many :app_table_columns, dependent: :destroy
  
  validates :name, presence: true, uniqueness: { scope: :app_id }
  validates :name, format: { with: /\A[a-zA-Z][a-zA-Z0-9_]*\z/, message: "must start with a letter and contain only letters, numbers, and underscores" }
  
  def supabase_table_name
    "app_#{app.id}_#{name}"
  end
  
  def schema
    app_table_columns.order(:created_at).map do |column|
      {
        name: column.name,
        type: column.column_type,
        required: column.required,
        default: column.default_value,
        options: column.options ? JSON.parse(column.options) : {}
      }
    end
  end
  
  def create_in_supabase!
    Supabase::AppDatabaseService.new(app).create_table(name, schema)
  end
  
  def drop_from_supabase!
    Supabase::AppDatabaseService.new(app).drop_table(name)
  end
end
