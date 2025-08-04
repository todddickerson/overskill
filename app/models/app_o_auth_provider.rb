class AppOAuthProvider < ApplicationRecord
  belongs_to :app
  
  SUPPORTED_PROVIDERS = %w[google github auth0].freeze
  
  validates :provider, presence: true, inclusion: { in: SUPPORTED_PROVIDERS }
  validates :client_id, presence: true
  validates :client_secret, presence: true
  validates :redirect_uri, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp }
  validates :provider, uniqueness: { scope: :app_id }
  
  encrypts :client_secret
  
  def scopes_array
    return [] unless scopes.present?
    scopes.split(',').map(&:strip)
  end
  
  def scopes_array=(array)
    self.scopes = array.join(',') if array.is_a?(Array)
  end
  
  def worker_env_vars
    case provider
    when 'google'
      {
        'GOOGLE_CLIENT_ID' => client_id,
        'GOOGLE_CLIENT_SECRET' => client_secret
      }
    when 'github'
      {
        'GITHUB_CLIENT_ID' => client_id,
        'GITHUB_CLIENT_SECRET' => client_secret
      }
    when 'auth0'
      {
        'AUTH0_CLIENT_ID' => client_id,
        'AUTH0_CLIENT_SECRET' => client_secret,
        'AUTH0_DOMAIN' => domain
      }
    else
      {}
    end
  end
  
  def generate_worker_code
    service = Cloudflare::WorkerGeneratorService.new(app)
    service.generate_oauth_worker(provider: provider, redirect_uri: redirect_uri)
  end
  
  def provider_display_name
    case provider
    when 'google' then 'Google'
    when 'github' then 'GitHub'
    when 'auth0' then 'Auth0'
    else provider.titleize
    end
  end
  
  def provider_icon
    case provider
    when 'google' then 'fab fa-google'
    when 'github' then 'fab fa-github'
    when 'auth0' then 'fas fa-shield-alt'
    else 'fas fa-key'
    end
  end
  
  def default_scopes
    case provider
    when 'google' then ['openid', 'email', 'profile']
    when 'github' then ['user:email']
    when 'auth0' then ['openid', 'profile', 'email']
    else []
    end
  end
end
