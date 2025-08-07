class Avo::Resources::AppAuthSetting < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :visibility, as: :number
    field :allowed_providers, as: :textarea
    field :allowed_email_domains, as: :textarea
    field :require_email_verification, as: :boolean
    field :allow_signups, as: :boolean
    field :allow_anonymous, as: :boolean
  end
end
