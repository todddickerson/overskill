class Avo::Resources::IntegrationsGoogleOauth2Installation < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  self.model_class = ::Integrations::GoogleOauth2Installation
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :oauth_google_oauth2_account, as: :belongs_to
    field :name, as: :text
  end
end
