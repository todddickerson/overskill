#!/usr/bin/env rails runner

app = App.find(109)
puts "Testing production deployment for app: #{app.name}"

begin
  result = app.publish_to_production!
  puts "Result: #{result.inspect}"
rescue => e
  puts "Error: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
end