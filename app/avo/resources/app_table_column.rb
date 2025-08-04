class Avo::Resources::AppTableColumn < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app_table, as: :belongs_to
    field :name, as: :text
    field :column_type, as: :text
    field :options, as: :textarea
    field :required, as: :boolean
    field :default_value, as: :text
  end
end
