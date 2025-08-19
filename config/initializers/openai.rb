if openai_enabled?
  OpenAI.configure do |config|
    config.access_token = ENV["OPENAI_ACCESS_TOKEN"]
    config.organization_id = ENV["OPENAI_ORGANIZATION_ID"] if openai_organization_exists?

    # Set request timeout for image generation (gpt-image-1 can take 2-4 minutes)
    # Default is 120 seconds, but 2025 best practice is 240s for image generation
    config.request_timeout = 240  # 4 minutes for image generation
  end
end
