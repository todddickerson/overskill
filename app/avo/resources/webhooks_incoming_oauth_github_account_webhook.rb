class Avo::Resources::WebhooksIncomingOauthGithubAccountWebhook < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  self.model_class = ::Webhooks::Incoming::Oauth::GithubAccountWebhook
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :data, as: :code
    field :processed_at, as: :date_time
    field :verified_at, as: :date_time
    field :oauth_github_account, as: :belongs_to
  end
end
