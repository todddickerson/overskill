#!/usr/bin/env rails runner

# Script to diagnose and fix GitHub App authentication issues

puts "=" * 60
puts "GitHub App Authentication Diagnostics"
puts "=" * 60

# Check environment variables
puts "\n1. Environment Variables Check:"
puts "-" * 40

env_vars = {
  'GITHUB_APP_PRIVATE_KEY' => ENV['GITHUB_APP_PRIVATE_KEY'],
  'GITHUB_PRIVATE_KEY' => ENV['GITHUB_PRIVATE_KEY'],
  'GITHUB_TOKEN' => ENV['GITHUB_TOKEN'],
  'GITHUB_ORG' => ENV['GITHUB_ORG'],
  'GITHUB_TEMPLATE_REPO' => ENV['GITHUB_TEMPLATE_REPO']
}

env_vars.each do |name, value|
  if value.present?
    if name.include?('KEY')
      # For keys, show first/last few chars
      display = if value.include?('BEGIN')
                  "Present (#{value.lines.first.strip}...)"
                else
                  "Present (#{value[0..20]}...)"
                end
    else
      display = value
    end
    puts "✅ #{name}: #{display}"
  else
    puts "❌ #{name}: Missing"
  end
end

# Test authenticator directly
puts "\n2. Direct Authenticator Test:"
puts "-" * 40

begin
  authenticator = Deployment::GithubAppAuthenticator.new
  token = authenticator.get_installation_token
  
  if token
    puts "✅ Installation token generated successfully"
    puts "   Token: #{token[0..20]}..."
  else
    puts "❌ Failed to generate installation token"
  end
rescue => e
  puts "❌ Authenticator error: #{e.message}"
  puts "   #{e.backtrace.first}"
end

# Test repository service
puts "\n3. Repository Service Test:"
puts "-" * 40

begin
  # Find a test app
  test_app = App.last
  if test_app
    puts "Using app: #{test_app.name} (ID: #{test_app.id})"
    
    # Try to create repository service
    repo_service = Deployment::GithubRepositoryService.new(test_app)
    puts "✅ Repository service created successfully"
    
    # Try to get repository info if it exists
    if test_app.repository_name.present?
      info = repo_service.get_repository_info
      if info[:success]
        puts "✅ Can access repository: #{test_app.repository_name}"
      else
        puts "⚠️  Cannot access repository: #{info[:error]}"
      end
    end
  else
    puts "⚠️  No apps found for testing"
  end
rescue => e
  puts "❌ Repository service error: #{e.message}"
  puts "   #{e.backtrace.first}"
end

# Check if private key needs formatting
puts "\n4. Private Key Format Check:"
puts "-" * 40

private_key = ENV['GITHUB_APP_PRIVATE_KEY'] || ENV['GITHUB_PRIVATE_KEY']

if private_key.present?
  # Check if key has proper line breaks
  if private_key.include?('\n') && !private_key.include?("\n")
    puts "⚠️  Private key appears to have escaped newlines (\\n instead of actual line breaks)"
    puts "   This can happen when copying from environment variables"
    
    # Try to fix it
    fixed_key = private_key.gsub('\n', "\n")
    
    begin
      # Test the fixed key
      OpenSSL::PKey::RSA.new(fixed_key)
      puts "✅ Fixed key format is valid!"
      puts "\n   To fix permanently, update your .env file with proper line breaks"
    rescue => e
      puts "❌ Fixed key still invalid: #{e.message}"
    end
  else
    # Try to parse the key
    begin
      OpenSSL::PKey::RSA.new(private_key)
      puts "✅ Private key format is valid"
    rescue => e
      puts "❌ Private key format is invalid: #{e.message}"
    end
  end
else
  puts "❌ No private key found in environment"
end

# Test in background job context
puts "\n5. Background Job Context Test:"
puts "-" * 40

begin
  # Simulate what happens in the job
  app = App.last
  if app
    puts "Testing with app: #{app.name}"
    
    # This simulates what DeployAppJob does
    github_service = Deployment::GithubRepositoryService.new(app)
    puts "✅ Service creation successful in job context"
  else
    puts "⚠️  No apps available for job context test"
  end
rescue => e
  puts "❌ Job context error: #{e.message}"
  puts "   This is the error you're seeing in DeployAppJob"
  puts "\n   Full backtrace:"
  puts e.backtrace[0..5].join("\n   ")
end

puts "\n" + "=" * 60
puts "Diagnostics Complete"
puts "=" * 60