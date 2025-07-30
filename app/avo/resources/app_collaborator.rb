class Avo::Resources::AppCollaborator < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :app, as: :belongs_to
    field :membership, as: :belongs_to
    field :role, as: :text
    field :github_username, as: :text
    field :permissions_synced, as: :boolean
  end
end
