# GitHub App Authenticator
# Generates installation tokens for GitHub App authentication

require 'jwt'
require 'httparty'

class Deployment::GithubAppAuthenticator
  include HTTParty
  base_uri 'https://api.github.com'
  
  APP_ID = '1815066'
  CLIENT_ID = 'Iv23linLjuIIrIXD6pC7'
  
  def initialize
    @app_id = APP_ID
    @client_id = CLIENT_ID
    @private_key = ENV['GITHUB_APP_PRIVATE_KEY'] || ENV['GITHUB_PRIVATE_KEY']
    @client_secret = ENV['GITHUB_TOKEN'] # The f1a5b01859... token
  end
  
  def get_installation_token(organization = nil)
    organization ||= ENV['GITHUB_ORG'] || 'Overskill-apps'
    
    # First, we need to generate a JWT for the app
    jwt = generate_jwt
    
    if jwt.nil?
      Rails.logger.error "[GithubAppAuthenticator] Failed to generate JWT - check GITHUB_APP_PRIVATE_KEY environment variable"
      return nil
    end
    
    # Get the installation ID for the organization
    installation_id = get_installation_id(organization, jwt)
    
    unless installation_id
      Rails.logger.error "[GithubAppAuthenticator] Failed to get installation ID for organization: #{organization}"
      return nil
    end
    
    # Generate an installation access token
    token = generate_installation_token(installation_id, jwt)
    
    if token.nil?
      Rails.logger.error "[GithubAppAuthenticator] Failed to generate installation token for installation ID: #{installation_id}"
    else
      Rails.logger.info "[GithubAppAuthenticator] Successfully generated installation token for #{organization}"
    end
    
    token
  end
  
  def test_authentication
    puts "🔑 GitHub App Authentication Test"
    puts "=" * 60
    
    puts "App ID: #{@app_id}"
    puts "Client ID: #{@client_id}"
    puts "Client Secret: #{@client_secret&.slice(0, 10)}..."
    puts "Private Key: #{@private_key.present? ? 'Present' : 'Missing'}"
    
    if @private_key.blank?
      puts "\n❌ Private key is missing!"
      puts "\nTo fix this:"
      puts "1. Go to: https://github.com/organizations/Overskill-apps/settings/apps/Overskill-App-Builder"
      puts "2. Scroll to 'Private keys' section"
      puts "3. Click 'Generate a private key'"
      puts "4. Download the .pem file"
      puts "5. Add to .env.local:"
      puts '   GITHUB_APP_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----"'
      return false
    end
    
    # Try to get an installation token
    token = get_installation_token
    
    if token
      puts "\n✅ Successfully generated installation token!"
      puts "Token: #{token.slice(0, 20)}..."
      
      # Test the token
      test_response = self.class.get('/user',
        headers: {
          'Authorization' => "token #{token}",
          'Accept' => 'application/vnd.github.v3+json'
        }
      )
      
      if test_response.code == 200
        puts "Token type: GitHub App Installation Token"
        puts "Works for: #{ENV['GITHUB_ORG']} repositories"
      end
      
      # List accessible repos
      repos_response = self.class.get('/installation/repositories',
        headers: {
          'Authorization' => "token #{token}",
          'Accept' => 'application/vnd.github.v3+json'
        }
      )
      
      if repos_response.success?
        puts "\n📦 Accessible repositories:"
        repos_response['repositories'].each do |repo|
          puts "  - #{repo['full_name']}"
        end
      end
      
      return token
    else
      puts "\n❌ Failed to generate installation token"
      return false
    end
  end
  
  private
  
  def generate_jwt
    return nil unless @private_key.present?
    
    payload = {
      iat: Time.now.to_i - 60,  # Issued at time (60 seconds in the past to allow for clock drift)
      exp: Time.now.to_i + (10 * 60),  # JWT expiration time (10 minute maximum)
      iss: @app_id  # GitHub App ID
    }
    
    JWT.encode(payload, OpenSSL::PKey::RSA.new(@private_key), 'RS256')
  rescue => e
    Rails.logger.error "[GithubAppAuthenticator] Error generating JWT: #{e.message}"
    nil
  end
  
  def get_installation_id(organization, jwt)
    response = self.class.get("/orgs/#{organization}/installation",
      headers: {
        'Authorization' => "Bearer #{jwt}",
        'Accept' => 'application/vnd.github.v3+json'
      }
    )
    
    if response.success?
      response['id']
    else
      Rails.logger.warn "[GithubAppAuthenticator] Failed to get installation ID: #{response.code} - #{response.message}"
      
      # Try listing all installations
      all_installations = self.class.get('/app/installations',
        headers: {
          'Authorization' => "Bearer #{jwt}",
          'Accept' => 'application/vnd.github.v3+json'
        }
      )
      
      if all_installations.success?
        Rails.logger.info "[GithubAppAuthenticator] Found #{all_installations.size} installations"
        all_installations.each do |inst|
          if inst['account']['login'] == organization
            Rails.logger.info "[GithubAppAuthenticator] Found matching installation for #{organization} (ID: #{inst['id']})"
            return inst['id']
          end
        end
      end
      
      nil
    end
  end
  
  def generate_installation_token(installation_id, jwt, retry_count = 0)
    response = self.class.post("/app/installations/#{installation_id}/access_tokens",
      headers: {
        'Authorization' => "Bearer #{jwt}",
        'Accept' => 'application/vnd.github.v3+json'
      }
    )
    
    if response.success?
      response['token']
    elsif response.code == 500 && retry_count < 3
      # GitHub API sometimes returns 500 errors transiently
      Rails.logger.warn "[GithubAppAuthenticator] Got 500 error from GitHub API, retrying (attempt #{retry_count + 1}/3)"
      sleep(1 * (retry_count + 1)) # Exponential backoff: 1s, 2s, 3s
      generate_installation_token(installation_id, jwt, retry_count + 1)
    else
      error_msg = "Failed to generate installation token: #{response.code} - #{response.message}"
      Rails.logger.error "[GithubAppAuthenticator] #{error_msg}"
      Rails.logger.error "[GithubAppAuthenticator] Response body: #{response.body}" if response.body.present?
      nil
    end
  end
end