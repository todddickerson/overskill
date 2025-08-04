class Avo::Resources::AppOAuthProvider < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :provider, as: :text
    field :client_id, as: :text
    field :client_secret, as: :text
    field :domain, as: :text
    field :redirect_uri, as: :text
    field :scopes, as: :textarea
    field :enabled, as: :boolean
  end
end
