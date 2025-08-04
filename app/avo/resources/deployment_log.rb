class Avo::Resources::DeploymentLog < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :environment, as: :text
    field :status, as: :text
    field :initiated_by, as: :belongs_to
    field :deployment_url, as: :text
    field :error_message, as: :textarea
    field :started_at, as: :date_time
    field :completed_at, as: :date_time
    field :rollback_from, as: :belongs_to
    field :deployed_version, as: :text
    field :build_output, as: :textarea
  end
end
