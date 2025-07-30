class Avo::Resources::AppChatMessage < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :content, as: :textarea
    field :role, as: :text
    field :response, as: :textarea
    field :status, as: :text
  end
end
