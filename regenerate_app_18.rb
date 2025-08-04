#!/usr/bin/env ruby

# Script to regenerate app 18 with improved AI orchestration
require_relative 'config/environment'

puts "=== APP 18 REGENERATION SCRIPT ==="

app = App.find(18)
puts "Found app: #{app.name}"
puts "Current status: #{app.status}"
puts "Current files: #{app.app_files.count}"
puts "Current prompt: #{app.prompt[0..200]}..."

# Create new generation record
generation = app.app_generations.create!(
  team: app.team,
  prompt: app.prompt,
  status: "pending",
  started_at: Time.current
)

puts "Created generation #{generation.id}"

# Queue the job
AppGenerationJob.perform_later(generation)
puts "Generation job queued!"

puts "Monitor progress by checking:"
puts "- App status: App.find(18).status"
puts "- Generation status: AppGeneration.find(#{generation.id}).status"
puts "- Job queue: Sidekiq web interface or rails console"