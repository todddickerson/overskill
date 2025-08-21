app = App.create!(
  team_id: 181,
  creator_id: 181,
  name: "Final Test #{Time.now.to_i}",
  description: "Testing complete workflow with fixes",
  prompt: "A simple counter app",
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "Created app #{app.id}: #{app.name}"

# Queue generation job
message = app.app_chat_messages.create!(
  role: 'user',
  content: "Create a simple counter app with increment and decrement buttons. Keep it minimal."
)

ProcessAppUpdateJobV4.perform_later(message)
puts "Queued ProcessAppUpdateJobV4 for message #{message.id}"