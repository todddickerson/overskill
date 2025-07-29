class Avo::Resources::App < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :name, as: :text
    field :slug, as: :text
    field :description, as: :textarea
    field :creator, as: :belongs_to
    field :prompt, as: :textarea
    field :app_type, as: :text
    field :framework, as: :text
    field :status, as: :text
    field :visibility, as: :text
    field :base_price, as: :number
    field :stripe_product_id, as: :belongs_to
    field :preview_url, as: :text
    field :production_url, as: :text
    field :github_repo, as: :text
    field :total_users, as: :number
    field :total_revenue, as: :number
    field :rating, as: :number
    field :featured, as: :boolean
    field :featured_until, as: :date_time
    field :launch_date, as: :date_time
    field :ai_model, as: :text
    field :ai_cost, as: :number
  end
end
