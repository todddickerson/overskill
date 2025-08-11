app = App.find(159)

puts "Current app name: #{app.name}"
puts "App status: #{app.status}"
puts "\nAll chat messages:"
app.app_chat_messages.order(created_at: :asc).each do |msg|
  puts "[#{msg.created_at.strftime('%H:%M:%S')}] #{msg.role}: #{msg.content[0..150]}"
  puts "  Status: #{msg.status}" if msg.status
  puts ""
end

# Check if the app naming job completed
puts "\nChecking recent logs for AppNamingJob..."
if app.name != "Todo App 1754936013"
  puts "✅ App was renamed to: #{app.name}"
else
  puts "⚠️ App still has original name"
end

# Check auth settings
if app.app_auth_setting
  puts "\n✅ Auth settings exist:"
  puts "  Visibility: #{app.app_auth_setting.visibility}"
else
  puts "\n⚠️ No auth settings created"
end