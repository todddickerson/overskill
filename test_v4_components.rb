#!/usr/bin/env ruby
# Standalone test to verify V4 components work without database issues

require 'bundler/setup'
require 'active_support/all'
require 'pathname'
require 'logger'
require 'ostruct'
require 'json'
require 'fileutils'

# Set up Rails-like environment
module Rails
  def self.root
    Pathname.new(File.expand_path('.', __dir__))
  end
  
  def self.logger
    @logger ||= Logger.new(STDOUT)
  end
  
  def self.env
    ActiveSupport::StringInquirer.new('test')
  end
  
  def self.application
    credentials_data = {
      cloudflare: {
        account_id: 'test_account',
        zone_id: 'test_zone',
        api_token: 'test_token'
      },
      supabase: {
        url: 'https://test.supabase.co',
        service_key: 'test_key'
      }
    }
    
    credentials = OpenStruct.new
    credentials.define_singleton_method(:dig) do |*keys|
      result = credentials_data
      keys.each do |key|
        result = result[key] if result
      end
      result || 'test_value'
    end
    
    OpenStruct.new(credentials: credentials)
  end
end

# Load HTTParty for API clients
require 'httparty'

# Test results tracker
test_results = []

puts "\n" + "=" * 60
puts "V4 COMPONENT VERIFICATION TEST"
puts "=" * 60

# Test 1: ExternalViteBuilder loads and initializes
puts "\n✅ Testing ExternalViteBuilder..."
begin
  require_relative 'app/services/deployment/external_vite_builder'
  
  # Mock app object
  app = OpenStruct.new(
    id: 123,
    name: 'Test App',
    app_files: [],
    team: OpenStruct.new(id: 1)
  )
  
  builder = Deployment::ExternalViteBuilder.new(app)
  
  # Test temp directory creation
  temp_dir = builder.send(:create_temp_directory)
  raise "Temp dir not created" unless Dir.exist?(temp_dir)
  FileUtils.rm_rf(temp_dir) if Dir.exist?(temp_dir)
  
  # Test HTML generation
  html = builder.send(:generate_default_html)
  raise "HTML not generated" unless html.include?('<!DOCTYPE html>')
  
  # Test Worker wrapping
  wrapped = builder.send(:wrap_for_worker_deployment, 'console.log("test");')
  raise "Not wrapped for Worker" unless wrapped.include?('export default')
  raise "Missing secrets injection" unless wrapped.include?('SUPABASE_SECRET_KEY')
  
  puts "  ✓ ExternalViteBuilder works correctly"
  test_results << { service: 'ExternalViteBuilder', status: 'PASS' }
rescue => e
  puts "  ✗ Error: #{e.message}"
  puts "  #{e.backtrace.first}"
  test_results << { service: 'ExternalViteBuilder', status: 'FAIL', error: e.message }
end

# Test 2: CloudflareWorkersDeployer loads and initializes
puts "\n✅ Testing CloudflareWorkersDeployer..."
begin
  require_relative 'app/services/deployment/cloudflare_workers_deployer'
  
  app = OpenStruct.new(
    id: 123,
    name: 'Test App',
    team: OpenStruct.new(id: 1),
    custom_domain: nil
  )
  
  deployer = Deployment::CloudflareWorkersDeployer.new(app)
  
  # Test worker name generation
  preview_name = deployer.send(:generate_worker_name, :preview)
  raise "Wrong preview name" unless preview_name == "preview-app-123"
  
  production_name = deployer.send(:generate_worker_name, :production)
  raise "Wrong production name" unless production_name == "app-123"
  
  # Test secrets gathering
  secrets = deployer.send(:gather_all_secrets)
  raise "Missing APP_ID" unless secrets['APP_ID'] == '123'
  raise "Missing SUPABASE_URL" unless secrets['SUPABASE_URL']
  
  # Test worker body building
  body = deployer.send(:build_worker_upload_body, 'test code')
  raise "Missing metadata" unless body['metadata']
  raise "Missing script" unless body['index.js']
  
  puts "  ✓ CloudflareWorkersDeployer works correctly"
  test_results << { service: 'CloudflareWorkersDeployer', status: 'PASS' }
rescue => e
  puts "  ✗ Error: #{e.message}"
  puts "  #{e.backtrace.first}"
  test_results << { service: 'CloudflareWorkersDeployer', status: 'FAIL', error: e.message }
end

# Test 3: Updated AppBuilderV4 with new methods
puts "\n✅ Testing Updated AppBuilderV4..."
begin
  require_relative 'app/services/ai/app_builder_v4'
  
  # Create mock objects
  app_versions = []
  app = OpenStruct.new(
    id: 123,
    name: 'Test App',
    team: OpenStruct.new(id: 1),
    app_files: [],
    app_chat_messages: [],
    status: 'generating'
  )
  
  # Add mock methods
  app.define_singleton_method(:update!) do |attrs|
    true
  end
  
  app.app_versions = OpenStruct.new
  app.app_versions.define_singleton_method(:create!) do |attrs|
    version = OpenStruct.new(attrs.merge(id: 1, created_at: Time.now))
    app_versions << version
    version
  end
  
  app.app_versions.define_singleton_method(:order) do |field|
    OpenStruct.new(last: app_versions.last)
  end
  
  message = OpenStruct.new(
    app: app,
    content: 'Build a todo app',
    user: OpenStruct.new(id: 1)
  )
  
  builder = Ai::AppBuilderV4.new(message)
  
  # Test that new methods exist
  raise "Missing build_for_deployment" unless builder.respond_to?(:build_for_deployment, true)
  raise "Missing deploy_to_workers_with_secrets" unless builder.respond_to?(:deploy_to_workers_with_secrets, true)
  raise "Missing update_app_urls_for_deployment_type" unless builder.respond_to?(:update_app_urls_for_deployment_type, true)
  
  puts "  ✓ AppBuilderV4 updated with hybrid architecture"
  test_results << { service: 'AppBuilderV4', status: 'PASS' }
rescue => e
  puts "  ✗ Error: #{e.message}"
  puts "  #{e.backtrace.first}"
  test_results << { service: 'AppBuilderV4', status: 'FAIL', error: e.message }
end

# Test 4: Integration test - services work together
puts "\n✅ Testing Service Integration..."
begin
  app = OpenStruct.new(
    id: 123,
    name: 'Test App',
    team: OpenStruct.new(id: 1),
    app_files: [],
    custom_domain: nil,
    update!: ->(attrs) { true }
  )
  
  # Test that ExternalViteBuilder output can be used by CloudflareWorkersDeployer
  builder = Deployment::ExternalViteBuilder.new(app)
  wrapped_code = builder.send(:wrap_for_worker_deployment, 'console.log("app");')
  
  raise "Code not wrapped" unless wrapped_code.include?('export default')
  raise "Missing fetch handler" unless wrapped_code.include?('async fetch(request, env, ctx)')
  
  # Test deployer can process the wrapped code
  deployer = Deployment::CloudflareWorkersDeployer.new(app)
  body = deployer.send(:build_worker_upload_body, wrapped_code)
  
  raise "Body not prepared" unless body['index.js'][:content] == wrapped_code
  
  puts "  ✓ Services integrate correctly"
  test_results << { service: 'Integration', status: 'PASS' }
rescue => e
  puts "  ✗ Error: #{e.message}"
  puts "  #{e.backtrace.first}"
  test_results << { service: 'Integration', status: 'FAIL', error: e.message }
end

# Summary
puts "\n" + "=" * 60
puts "TEST RESULTS SUMMARY"
puts "=" * 60

test_results.each do |result|
  status_icon = result[:status] == 'PASS' ? '✅' : '❌'
  puts "#{status_icon} #{result[:service]}: #{result[:status]}"
  puts "   Error: #{result[:error]}" if result[:error]
end

total = test_results.size
passed = test_results.count { |r| r[:status] == 'PASS' }
failed = test_results.count { |r| r[:status] == 'FAIL' }

puts "\nTotal: #{total} | Passed: #{passed} | Failed: #{failed}"

if failed == 0
  puts "\n🎉 All V4 components are working correctly!"
  exit 0
else
  puts "\n⚠️  Some components need attention"
  exit 1
end