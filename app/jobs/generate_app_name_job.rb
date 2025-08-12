class GenerateAppNameJob < ApplicationJob
  queue_as :default

  def perform(app_id)
    app = App.find(app_id)
    
    # Skip if app already has a good name (not default/generic)
    if has_good_name?(app)
      Rails.logger.info "[AppName] Skipping name generation for app #{app.id} - already has good name: '#{app.name}'"
      return
    end

    service = Ai::AppNamerService.new(app)
    result = service.generate_name!

    if result[:success]
      app.update(name_generated_at: Time.current)
      Rails.logger.info "[AppName] Successfully generated name for app: #{result[:new_name]}"
    else
      Rails.logger.error "[AppName] Failed to generate name for app #{app.id}: #{result[:error]}"
    end
  rescue => e
    Rails.logger.error "[AppName] Exception in GenerateAppNameJob: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def has_good_name?(app)
    return false if app.name.blank?
    
    # Check if name looks auto-generated or generic
    generic_patterns = [
      /^App \d+$/i,                    # "App 123"
      /^New App$/i,                    # "New App"
      /^Untitled App$/i,               # "Untitled App"
      /^My App$/i,                     # "My App"
      /^Test App$/i,                   # "Test App"
      /^Draft \d+$/i,                  # "Draft 123"
      /^Application$/i,                # "Application"
      /^\w{8}-\w{4}-\w{4}-\w{4}-\w{12}$/  # UUID-like
    ]
    
    # If name matches any generic pattern, it needs a better name
    return false if generic_patterns.any? { |pattern| app.name.match?(pattern) }
    
    # If name was recently generated, don't regenerate
    return true if app.name_generated_at && app.name_generated_at > 1.day.ago
    
    # If name is descriptive (more than 2 words or contains meaningful content), keep it
    return true if app.name.split.length > 2
    
    # If name seems intentionally set by user (contains creative elements), keep it
    creative_indicators = [
      /[A-Z][a-z]+[A-Z]/,  # CamelCase like "TaskFlow"
      /\w+ly$/,            # Ends with "ly" like "Quickly"
      /\w+er$/,            # Ends with "er" like "Tracker"
      /\w+hub$/i,          # Ends with "hub" like "TaskHub"
      /\w+pro$/i,          # Ends with "pro" like "BudgetPro"
    ]
    
    return true if creative_indicators.any? { |pattern| app.name.match?(pattern) }
    
    # Default to generating a new name for short, generic names
    false
  end
end
