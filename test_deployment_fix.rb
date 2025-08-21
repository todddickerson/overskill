#!/usr/bin/env rails runner

# Test the deployment fix for cloudflare_worker_name error
app = App.create!(
  team_id: 181,
  creator_id: 181,
  name: "Deployment Test #{Time.now.to_i}",
  description: "Testing deployment fix",
  prompt: "A simple counter app",
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "✅ Created app #{app.id}: #{app.name}"
puts "   Obfuscated ID: #{app.obfuscated_id}"

# Queue generation job
message = app.app_chat_messages.create!(
  role: 'user',
  content: "Create a simple counter app with increment and decrement buttons."
)

ProcessAppUpdateJobV4.perform_later(message)
puts "✅ Queued ProcessAppUpdateJobV4 for message #{message.id}"
puts ""
puts "📊 Watch for errors:"
puts "rails runner \"app = App.find(#{app.id}); msg = app.app_chat_messages.last; puts msg.status; puts msg.content if msg.status == 'failed'\""