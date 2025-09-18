class AppApiIntegration < ApplicationRecord
  belongs_to :app

  AUTH_TYPES = %w[bearer api_key basic custom none].freeze

  validates :name, presence: true, uniqueness: {scope: :app_id}
  validates :base_url, presence: true, format: {with: URI::DEFAULT_PARSER.make_regexp}
  validates :auth_type, presence: true, inclusion: {in: AUTH_TYPES}
  validates :path_prefix, presence: true, format: {with: /\A[a-zA-Z0-9_-]+\z/, message: "must contain only letters, numbers, hyphens, and underscores"}
  validates :api_key, presence: true, if: -> { auth_type.in?(["bearer", "api_key", "basic"]) }

  encrypts :api_key

  def parsed_additional_headers
    return {} unless additional_headers.present?
    JSON.parse(additional_headers)
  rescue JSON::ParserError
    {}
  end

  def parsed_additional_headers=(hash)
    self.additional_headers = hash.to_json if hash.is_a?(Hash)
  end

  def env_key
    "#{name.upcase.gsub(/[^A-Z0-9]/, "_")}_API_KEY"
  end

  def worker_env_vars
    return {} unless api_key.present?
    {env_key => api_key}
  end

  def api_config
    {
      name: name,
      path: path_prefix,
      base_url: base_url,
      auth_type: auth_type,
      env_key: env_key,
      additional_headers: parsed_additional_headers
    }.tap do |config|
      case auth_type
      when "api_key"
        config[:api_key_header] = api_key_header.presence || "X-API-Key"
      when "custom"
        config[:custom_auth_code] = custom_auth_code
      end
    end
  end

  def generate_worker_code(integrations_array)
    service = Cloudflare::WorkerGeneratorService.new(app)
    service.generate_api_proxy_worker(integrations_array.map(&:api_config))
  end

  # Common API integrations with defaults
  def self.preset_configs
    {
      "stripe" => {
        name: "Stripe",
        base_url: "https://api.stripe.com/v1",
        auth_type: "bearer",
        path_prefix: "stripe",
        description: "Payment processing with Stripe"
      },
      "sendgrid" => {
        name: "SendGrid",
        base_url: "https://api.sendgrid.com/v3",
        auth_type: "bearer",
        path_prefix: "sendgrid",
        description: "Email delivery service"
      },
      "twilio" => {
        name: "Twilio",
        base_url: "https://api.twilio.com/2010-04-01",
        auth_type: "basic",
        path_prefix: "twilio",
        description: "SMS and voice communications"
      },
      "openai" => {
        name: "OpenAI",
        base_url: "https://api.openai.com/v1",
        auth_type: "bearer",
        path_prefix: "openai",
        description: "AI and language processing"
      },
      "airtable" => {
        name: "Airtable",
        base_url: "https://api.airtable.com/v0",
        auth_type: "bearer",
        path_prefix: "airtable",
        description: "Database and spreadsheet service"
      }
    }
  end
end
