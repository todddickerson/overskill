class Avo::Resources::AppApiCall < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :app, as: :belongs_to
    field :method, as: :text
    field :path, as: :text
    field :status_code, as: :number
    field :response_time, as: :number
    field :request_body, as: :textarea
    field :response_body, as: :textarea
    field :user_agent, as: :text
    field :ip_address, as: :text
    field :occurred_at, as: :date_time
  end
end
