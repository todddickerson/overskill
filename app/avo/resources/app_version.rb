class Avo::Resources::AppVersion < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :app, as: :belongs_to
    field :user, as: :belongs_to
    field :commit_sha, as: :text
    field :commit_message, as: :text
    field :version_number, as: :text
    field :changelog, as: :textarea
    field :files_snapshot, as: :textarea
    field :changed_files, as: :textarea
    field :external_commit, as: :boolean
    field :deployed, as: :boolean
    field :published_at, as: :date_time
  end
end
