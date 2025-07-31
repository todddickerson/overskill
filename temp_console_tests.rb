# Console test script to generate an app and confirm each step is working

app_generation = AppGeneration.last
app = app_generation.app

app_generator_service = Ai::AppGeneratorService.new(app, app_generation)

@generation = app_generation
@app = app

# generate! method 
@generation.update!(status: "generating")

# enhance_prompt method
enhanced_prompt = app_generator_service.enhance_prompt(@generation.prompt)

puts "enhanced_prompt: #{enhanced_prompt}"

# generate_with_ai method
ai_response = app_generator_service.generate_with_ai(enhanced_prompt)

puts "ai_response: #{ai_response}"

# parse_ai_response method
parsed_data = app_generator_service.parse_ai_response(ai_response[:content])

puts "parsed_data: #{parsed_data}"

security_scan_passed = app_generator_service.security_scan_passed?(parsed_data[:files])

puts "security_scan_passed: #{security_scan_passed}"

create_app_files = app_generator_service.create_app_files(parsed_data[:files])

puts "create_app_files: #{create_app_files}"

update_app_metadata = app_generator_service.update_app_metadata(parsed_data[:app])

puts "update_app_metadata: #{update_app_metadata}"

@generation.update!(
    completed_at: Time.current,
    status: "completed",
    ai_model: ai_response[:model],
    total_cost: (app_generator_service.calculate_cost(ai_response[:usage]) * 100).to_i, # Store as cents
    duration_seconds: (Time.current - @generation.started_at).to_i,
    input_tokens: ai_response[:usage]&.dig("prompt_tokens"),
    output_tokens: ai_response[:usage]&.dig("completion_tokens")
  )

  @app.update!(
    status: "generated",
    ai_model: ai_response[:model],
    ai_cost: app_generator_service.calculate_cost(ai_response[:usage])
  )

  puts "app_generation: #{@generation}"
  puts "app: #{@app}"


