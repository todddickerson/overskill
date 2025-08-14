class TestHeliconeJob < ApplicationJob
  def perform
    Rails.logger.info "===== HELICONE TEST IN JOB ====="
    Rails.logger.info "HELICONE_API_KEY present: #{ENV['HELICONE_API_KEY'].present?}"
    Rails.logger.info "HELICONE_API_KEY value: #{ENV['HELICONE_API_KEY']&.first(10)}..."
    
    # Test the AnthropicClient
    client = Ai::AnthropicClient.instance
    Rails.logger.info "AnthropicClient base_uri: #{Ai::AnthropicClient.base_uri}"
    
    # Test build_request_options
    options = client.build_request_options
    Rails.logger.info "Headers include Helicone-Auth: #{options[:headers].key?('Helicone-Auth')}"
    
    Rails.logger.info "===== END HELICONE TEST ====="
  end
end

# Run the job
TestHeliconeJob.perform_now