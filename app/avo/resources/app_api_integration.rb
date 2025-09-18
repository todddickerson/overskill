class Avo::Resources::AppApiIntegration < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :name, as: :text
    field :base_url, as: :text
    field :auth_type, as: :text
    field :api_key, as: :text
    field :path_prefix, as: :text
    field :additional_headers, as: :textarea
    field :enabled, as: :boolean
  end
end
