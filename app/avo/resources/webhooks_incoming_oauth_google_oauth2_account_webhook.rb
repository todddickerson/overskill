class Avo::Resources::WebhooksIncomingOauthGoogleOauth2AccountWebhook < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  self.model_class = ::Webhooks::Incoming::Oauth::GoogleOauth2AccountWebhook
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :data, as: :code
    field :processed_at, as: :date_time
    field :verified_at, as: :date_time
    field :oauth_google_oauth2_account, as: :belongs_to
  end
end
