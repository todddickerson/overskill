#!/usr/bin/env rails runner

# Create a new test app to verify fixed deployment
app = App.create!(
  team_id: 181,
  creator_id: 181,
  name: "Calculator Pro #{Time.now.to_i}",
  description: "Testing fixed deployment with proper React app serving",
  prompt: "A beautiful calculator app with modern UI",
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "✅ Created app #{app.id}: #{app.name}"
puts "   Obfuscated ID: #{app.obfuscated_id}"

# Queue generation job
message = app.app_chat_messages.create!(
  role: 'user',
  content: "Create a functional calculator app with a clean, modern interface. Include basic operations (+, -, *, /) and a clear button. Use React with TypeScript and Tailwind CSS for styling."
)

ProcessAppUpdateJobV4.perform_later(message)
puts "✅ Queued ProcessAppUpdateJobV4 for message #{message.id}"
puts ""
puts "📊 Monitoring deployment:"
puts "   GitHub: https://github.com/Overskill-apps/#{app.repository_name}"
puts "   Preview URL will be: https://preview-#{app.obfuscated_id.downcase}.overskill.app"
puts ""
puts "Run this to check deployment status:"
puts "rails runner \"app = App.find(#{app.id}); puts app.status; puts app.preview_url\""