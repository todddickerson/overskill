class Avo::Resources::OauthGithubAccount < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  self.model_class = ::Oauth::GithubAccount
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :uid, as: :text
    field :data, as: :code
    field :user, as: :belongs_to
  end
end
