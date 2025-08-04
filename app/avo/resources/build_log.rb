class Avo::Resources::BuildLog < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :deployment_log, as: :belongs_to
    field :level, as: :text
    field :message, as: :textarea
    field :created_at, as: :date_time
  end
end
