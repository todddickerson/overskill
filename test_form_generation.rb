#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(18)
message = app.app_chat_messages.build

puts "Model inspection:"
puts "- app.id: #{app.id}"
puts "- message.class: #{message.class}"
puts "- message.inspect: #{message.inspect}"

# Test what form_with expects
puts "\nForm model name:"
puts "- model_name.param_key: #{message.model_name.param_key}"
puts "- model_name.route_key: #{message.model_name.route_key}"
puts "- model_name.singular_route_key: #{message.model_name.singular_route_key}"

# Expected field name
puts "\nExpected field name for content:"
puts "- app_chat_message[content]"