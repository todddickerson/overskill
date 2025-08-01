class Avo::Resources::AppVersionFile < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :app_version, as: :belongs_to
    field :app_file, as: :belongs_to
    field :content, as: :textarea
    field :action, as: :text
  end
end
