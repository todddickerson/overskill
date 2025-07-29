class Avo::Resources::CreatorProfile < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :username, as: :text
    field :bio, as: :textarea
    field :level, as: :number
    field :total_earnings, as: :number
    field :total_sales, as: :number
    field :verification_status, as: :text
    field :featured_until, as: :date_time
    field :slug, as: :text
    field :stripe_account_id, as: :belongs_to
    field :public_email, as: :text
    field :website_url, as: :text
    field :twitter_handle, as: :text
    field :github_username, as: :text
  end
end
