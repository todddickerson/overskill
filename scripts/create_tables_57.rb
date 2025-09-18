#!/usr/bin/env ruby
# Create tables for App 57
# Run with: bin/rails runner scripts/create_tables_57.rb

app = App.find(57)
puts "Creating tables for App #{app.id}: #{app.name}..."

service = Supabase::AutoTableService.new(app)
result = service.ensure_tables_exist!

if result[:success]
  puts "✅ Tables created successfully:"
  result[:tables].each { |t| puts "  - #{t}" }

  # Update metadata
  app.app_tables.reload
  puts "\nMetadata updated:"
  app.app_tables.each do |table|
    puts "  • #{table.name} (#{table.app_table_columns.count} columns)"
  end
else
  puts "❌ Failed: #{result[:error]}"
end
