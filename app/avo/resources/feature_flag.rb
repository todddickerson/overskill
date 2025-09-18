class Avo::Resources::FeatureFlag < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :name, as: :text
    field :enabled, as: :boolean
    field :percentage, as: :number
    field :description, as: :textarea
  end
end
