class Avo::Resources::AppTable < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :name, as: :text
    field :description, as: :textarea
    field :created_at, as: :date_time
    field :updated_at, as: :date_time
  end
end
