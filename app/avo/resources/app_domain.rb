class Avo::Resources::AppDomain < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :domain, as: :text
    field :status, as: :text
    field :verified_at, as: :date_time
    field :ssl_status, as: :text
    field :cloudflare_zone_id, as: :text
    field :cloudflare_record_id, as: :text
  end
end
