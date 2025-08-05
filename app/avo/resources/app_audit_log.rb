class Avo::Resources::AppAuditLog < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :action_type, as: :text
    field :performed_by, as: :text
    field :target_resource, as: :text
    field :resource_id, as: :belongs_to
    field :change_details, as: :textarea
    field :ip_address, as: :text
    field :user_agent, as: :text
    field :occurred_at, as: :date_time
  end
end
