class Avo::Resources::AppFile < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }

  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :app, as: :belongs_to
    field :path, as: :text
    field :content, as: :textarea
    field :file_type, as: :text
    field :size_bytes, as: :number
    field :checksum, as: :text
    field :is_entry_point, as: :boolean
  end
end
