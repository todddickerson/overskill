namespace :v4 do
  desc "Test V4 Enhanced app generation with visual feedback"
  task test_enhanced: :environment do
    puts "Testing V4 Enhanced App Generation"
    puts "=" * 50

    # Find or create a test user
    user = User.first || User.create!(
      email: "test@example.com",
      password: "password123",
      name: "Test User"
    )

    team = user.teams.first || user.create_default_team

    # Create a test app
    app = team.apps.create!(
      name: "Test V4 Enhanced App",
      description: "Testing enhanced visual feedback"
    )

    # Create a chat message
    message = app.app_chat_messages.create!(
      role: "user",
      content: "Create a simple todo app with add and delete functionality"
    )

    puts "\nCreated test message ##{message.id} for app ##{app.id}"
    puts "\nTesting AppBuilderV4Enhanced directly..."

    # Test the enhanced builder directly
    builder = Ai::AppBuilderV4Enhanced.new(message)
    result = builder.execute!

    if result[:success]
      puts "\n✅ SUCCESS!"
      puts "App URL: #{result[:app].preview_url}"
      puts "Files generated: #{result[:app].app_files.count}"
    else
      puts "\n❌ FAILED!"
      puts "Error: #{result[:error]}"
    end

    puts "\nCheck logs for detailed progress tracking"
  end

  desc "Compare V4 standard vs enhanced"
  task compare: :environment do
    puts "Comparing V4 Standard vs Enhanced"
    puts "=" * 50

    user = User.first
    team = user.teams.first

    # Test standard V4
    app1 = team.apps.create!(name: "V4 Standard Test")
    message1 = app1.app_chat_messages.create!(
      role: "user",
      content: "Create a counter app"
    )

    puts "\n1. Testing V4 Standard..."
    start_time = Time.current
    builder1 = Ai::AppBuilderV4.new(message1)
    result1 = builder1.execute!
    time1 = Time.current - start_time

    # Test enhanced V4
    app2 = team.apps.create!(name: "V4 Enhanced Test")
    message2 = app2.app_chat_messages.create!(
      role: "user",
      content: "Create a counter app"
    )

    puts "\n2. Testing V4 Enhanced..."
    start_time = Time.current
    builder2 = Ai::AppBuilderV4Enhanced.new(message2)
    result2 = builder2.execute!
    time2 = Time.current - start_time

    puts "\n" + "=" * 50
    puts "COMPARISON RESULTS:"
    puts "=" * 50

    puts "\nV4 Standard:"
    puts "  Success: #{result1[:success]}"
    puts "  Time: #{time1.round(2)}s"
    puts "  Files: #{app1.app_files.count}"

    puts "\nV4 Enhanced:"
    puts "  Success: #{result2[:success]}"
    puts "  Time: #{time2.round(2)}s"
    puts "  Files: #{app2.app_files.count}"
    puts "  (includes real-time feedback)"

    puts "\nEnhanced version provides:"
    puts "  • Real-time file creation visibility"
    puts "  • Progress tracking with phases"
    puts "  • User-friendly error messages"
    puts "  • Interactive approval flow"
    puts "  • Dependency validation"
  end
end
