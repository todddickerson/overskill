puts "Testing partial path fix..."

# Check if partial exists
partial_path = "/Users/todddickerson/src/GitHub/overskill/app/views/account/app_editors/_version_action_buttons.html.erb"
if File.exist?(partial_path)
  puts "✅ Version action buttons partial exists"
else
  puts "❌ Version action buttons partial missing"
end

# Check if unified card partial exists  
unified_path = "/Users/todddickerson/src/GitHub/overskill/app/views/account/app_editors/_unified_version_card.html.erb"
if File.exist?(unified_path)
  puts "✅ Unified version card partial exists"
else
  puts "❌ Unified version card partial missing"
end

puts "Partial paths should now be correct!"