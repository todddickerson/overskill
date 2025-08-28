# Test script to verify text streaming during tool execution

user = User.first
team = user.teams.first

app = team.apps.create!(
  name: "TextStreamTest", 
  creator: user,
  prompt: "Create a simple todo app with React. Include a header, an input field to add todos, and a list to display them. Add buttons to mark todos as complete and delete them."
)

puts "Created App ID: #{app.id} (#{app.name})"

# Create initial message to trigger app generation
message = app.app_chat_messages.create!(
  user: User.first, 
  content: "Create a simple todo app with React. Include a header, an input field to add todos, and a list to display them. Add buttons to mark todos as complete and delete them."
)

puts "Created message ID: #{message.id}"
puts "Starting app generation..."

# Trigger the generation
ProcessAppUpdateJobV5.perform_later(message.id)

puts "Job enqueued. Check logs for streaming text during tool execution."
puts "App URL: https://dev.overskill.com/account/apps/#{app.id}/editor"