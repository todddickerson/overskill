# Test custom domain after DNS configuration
require 'httparty'

app = App.find(1)
puts "=== Testing Custom Domain Setup ==="
puts "App: #{app.name} (ID: #{app.id})"
puts "Current preview URL: #{app.preview_url}"

# Update preview to use custom domain
service = Deployment::CloudflarePreviewService.new(app)
result = service.update_preview!

if result[:success]
  puts "\n✅ Preview updated successfully!"
  puts "Preview URL: #{result[:preview_url]}"
  puts "Custom domain URL: #{result[:custom_domain_url]}"
  puts "Workers.dev URL: #{result[:note]}"
  
  # Reload app to get updated URL
  app.reload
  puts "\nApp preview URL updated to: #{app.preview_url}"
  
  # Test the custom domain
  puts "\n🌐 Testing custom domain..."
  begin
    response = HTTParty.get(app.preview_url, timeout: 10)
    puts "Status: #{response.code}"
    puts "Content-Type: #{response.headers['content-type']}"
    
    if response.code == 200
      puts "✅ Custom domain is working!"
      if response.body.include?("TodoFlow")
        puts "✅ TodoFlow app content verified!"
      end
    else
      puts "❌ Got status #{response.code}"
    end
  rescue => e
    puts "❌ Error: #{e.message}"
  end
  
  # Also test the workers.dev URL for comparison
  workers_url = app.preview_url.gsub('overskill.app', "#{app.id}.#{ENV['CLOUDFLARE_ACCOUNT_ID'].gsub('_', '-')}.workers.dev")
  puts "\n🔧 Testing workers.dev URL for comparison: #{workers_url}"
  begin
    response = HTTParty.get(workers_url.sub('preview-', 'preview-'), timeout: 5)
    puts "Workers.dev status: #{response.code}"
  rescue => e
    puts "Workers.dev error: #{e.message}"
  end
else
  puts "❌ Update failed: #{result[:error]}"
end

puts "\n📱 Your app should now be accessible at:"
puts "   #{app.preview_url}"