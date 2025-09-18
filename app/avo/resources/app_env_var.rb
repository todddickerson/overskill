class Avo::Resources::AppEnvVar < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :key, as: :text
    field :value, as: :text
    field :description, as: :textarea
    field :is_secret, as: :boolean
    field :is_system, as: :boolean
  end
end
