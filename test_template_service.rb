#!/usr/bin/env ruby
require_relative 'config/environment'

user = User.last
team = Team.last

if team.nil?
  team = Team.create!(name: "Test Team")
  user = User.create!(email: "test_template@example.com", password: "SecureP@ssw0rd!2024")
  team.memberships.create!(user: user, role_ids: ['admin'])
end

app = App.create!(
  name: "Test Template App", 
  slug: "test-template-#{Time.now.to_i}", 
  team: team, 
  creator: team.memberships.first, 
  prompt: "test"
)

puts "Created app: #{app.id}"

service = Ai::SharedTemplateService.new(app)
files = service.generate_core_files

puts "Generated #{files.size} files"

app.app_files.each do |f|
  status = f.content.nil? ? "NIL" : "#{f.content.size} chars"
  puts "  #{f.path}: #{status}"
end

# Show any files with blank content
blank_files = app.app_files.where(content: [nil, ''])
if blank_files.any?
  puts "\n⚠️ Files with blank content:"
  blank_files.each { |f| puts "  - #{f.path}" }
else
  puts "\n✅ All files have content"
end