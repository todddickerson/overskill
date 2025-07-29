class Avo::Resources::AppGeneration < Avo::BaseResource
  # self.includes = []
  # self.attachments = []
  # self.search = {
  #   query: -> { query.ransack(id_eq: params[:q], m: "or").result(distinct: false) }
  # }
  
  def fields
    field :id, as: :id
    field :team, as: :belongs_to
    field :app, as: :belongs_to
    field :prompt, as: :textarea
    field :enhanced_prompt, as: :textarea
    field :status, as: :text
    field :ai_model, as: :text
    field :started_at, as: :date_time
    field :completed_at, as: :date_time
    field :duration_seconds, as: :number
    field :input_tokens, as: :number
    field :output_tokens, as: :number
    field :total_cost, as: :number
    field :error_message, as: :textarea
    field :retry_count, as: :number
  end
end
