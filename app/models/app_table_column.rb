class AppTableColumn < ApplicationRecord
  belongs_to :app_table
  
  COLUMN_TYPES = %w[text number boolean date datetime select multiselect].freeze
  
  validates :name, presence: true, uniqueness: { scope: :app_table_id }
  validates :name, format: { with: /\A[a-zA-Z][a-zA-Z0-9_]*\z/, message: "must start with a letter and contain only letters, numbers, and underscores" }
  validates :column_type, inclusion: { in: COLUMN_TYPES }
  
  def supabase_type
    case column_type
    when 'text' then 'text'
    when 'number' then 'numeric'
    when 'boolean' then 'boolean'
    when 'date' then 'date'
    when 'datetime' then 'timestamp with time zone'
    when 'select', 'multiselect' then 'text'
    else 'text'
    end
  end
  
  def parsed_options
    return {} unless options.present?
    JSON.parse(options)
  rescue JSON::ParserError
    {}
  end
end
