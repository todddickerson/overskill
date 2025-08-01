# Check Cloudflare routes configuration
require 'httparty'

class CloudflareChecker
  include HTTParty
  base_uri 'https://api.cloudflare.com/client/v4'
  
  def initialize
    @zone_id = ENV['CLOUDFLARE_ZONE_ID']
    @api_key = ENV['CLOUDFLARE_API_KEY']
    @email = ENV['CLOUDFLARE_EMAIL']
    
    self.class.headers({
      'X-Auth-Email' => @email,
      'X-Auth-Key' => @api_key,
      'Content-Type' => 'application/json'
    })
  end
  
  def check_routes
    puts "=== Checking Cloudflare Worker Routes ==="
    puts "Zone ID: #{@zone_id}"
    
    # Get all routes
    response = self.class.get("/zones/#{@zone_id}/workers/routes")
    
    if response.code == 200
      routes = response['result'] || []
      puts "\nFound #{routes.length} routes:"
      
      routes.each do |route|
        puts "\nRoute ID: #{route['id']}"
        puts "Pattern: #{route['pattern']}"
        puts "Script: #{route['script']}"
        puts "Enabled: #{route['enabled'] != false}"
      end
      
      # Check for our preview route
      preview_route = routes.find { |r| r['pattern']&.include?('preview-1') }
      if preview_route
        puts "\n✅ Preview route found: #{preview_route['pattern']}"
      else
        puts "\n⚠️  No preview-1 route found"
      end
    else
      puts "Error: #{response.code} - #{response.body}"
    end
  end
  
  def check_dns
    puts "\n\n=== Checking DNS Records ==="
    
    response = self.class.get("/zones/#{@zone_id}/dns_records")
    
    if response.code == 200
      records = response['result'] || []
      wildcard = records.find { |r| r['name'] == '*.overskill.app' || r['name'] == '*' }
      
      if wildcard
        puts "✅ Wildcard DNS found:"
        puts "  Name: #{wildcard['name']}"
        puts "  Type: #{wildcard['type']}"
        puts "  Content: #{wildcard['content']}"
        puts "  Proxied: #{wildcard['proxied']}"
      else
        puts "⚠️  No wildcard DNS record found"
      end
    end
  end
end

checker = CloudflareChecker.new
checker.check_routes
checker.check_dns