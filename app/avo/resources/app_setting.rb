class Avo::Resources::AppSetting < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :key, as: :text
    field :value, as: :textarea
    field :encrypted, as: :boolean
    field :description, as: :textarea
    field :setting_type, as: :text
  end
end
