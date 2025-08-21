app = App.create!(
  team_id: 181,
  creator_id: 181,
  name: "Fixed Workflow Test #{Time.now.to_i}",
  description: "Testing workflow fix - should deploy successfully",
  prompt: "A simple calculator app",
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "Created app #{app.id}: #{app.name}"

# Queue generation job
message = app.app_chat_messages.create!(
  role: 'user',
  content: "Create a simple calculator app with basic operations (+, -, *, /). Keep it clean and minimal."
)

ProcessAppUpdateJobV4.perform_later(message)
puts "Queued ProcessAppUpdateJobV4 for message #{message.id}"