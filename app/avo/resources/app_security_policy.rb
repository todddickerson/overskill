class Avo::Resources::AppSecurityPolicy < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :policy_name, as: :text
    field :policy_type, as: :text
    field :enabled, as: :boolean
    field :configuration, as: :textarea
    field :description, as: :textarea
    field :last_violation, as: :date_time
    field :violation_count, as: :number
  end
end
