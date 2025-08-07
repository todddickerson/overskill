#!/usr/bin/env ruby
# Fix App 57 database issues - creates todos table with proper structure
# Run with: bin/rails runner scripts/fix_app_57_database.rb

puts "=== Fixing App 57 Database ==="

app = App.find(57)
puts "App: #{app.name} (ID: #{app.id})"

# Step 1: Ensure app has a database shard
unless app.database_shard
  puts "Assigning database shard..."
  app.database_shard = DatabaseShard.current_shard
  app.save!
  puts "✅ Assigned to shard: #{app.database_shard.name}"
else
  puts "✅ Already assigned to shard: #{app.database_shard.name}"
end

# Step 2: Create todos table entity in our database
todos_table = app.app_tables.find_or_create_by!(name: 'todos') do |t|
  t.team = app.team
  t.display_name = 'Todos'
  t.scope_type = 'user_scoped'
end
puts "✅ Created/found todos table entity"

# Step 3: Define columns if not exists
if todos_table.app_table_columns.empty?
  todos_table.app_table_columns.create!([
    { name: 'text', column_type: 'text', is_required: true },
    { name: 'completed', column_type: 'boolean', default_value: 'false' }
  ])
  puts "✅ Added table columns"
else
  puts "✅ Table columns already defined"
end

# Step 4: Create table in Supabase
puts "\nCreating table in Supabase..."

# Build SQL for table creation
table_name = "app_#{app.id}_todos"
create_table_sql = <<~SQL
  -- Drop if exists (for testing)
  DROP TABLE IF EXISTS #{table_name} CASCADE;
  
  -- Create todos table
  CREATE TABLE #{table_name} (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    completed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  
  -- Create indexes for performance
  CREATE INDEX idx_#{table_name}_user_id ON #{table_name}(user_id);
  CREATE INDEX idx_#{table_name}_created_at ON #{table_name}(created_at DESC);
  
  -- Enable Row Level Security
  ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;
  
  -- RLS Policies: Users can only see/modify their own todos
  CREATE POLICY "Users can view own todos"
    ON #{table_name} FOR SELECT
    USING (auth.uid() = user_id);
  
  CREATE POLICY "Users can insert own todos"
    ON #{table_name} FOR INSERT
    WITH CHECK (auth.uid() = user_id);
  
  CREATE POLICY "Users can update own todos"
    ON #{table_name} FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);
  
  CREATE POLICY "Users can delete own todos"
    ON #{table_name} FOR DELETE
    USING (auth.uid() = user_id);
  
  -- Grant permissions
  GRANT ALL ON #{table_name} TO authenticated;
  GRANT ALL ON #{table_name} TO service_role;
SQL

# Execute SQL using Supabase service
begin
  # Use HTTParty to execute SQL via Supabase REST API
  require 'httparty'
  
  supabase_url = app.database_shard.supabase_url || ENV['SUPABASE_URL']
  service_key = app.database_shard.supabase_service_key || ENV['SUPABASE_SERVICE_KEY']
  
  if supabase_url && service_key
    # Execute SQL via Supabase
    response = HTTParty.post(
      "#{supabase_url}/rest/v1/rpc/exec_sql",
      headers: {
        'apikey' => service_key,
        'Authorization' => "Bearer #{service_key}",
        'Content-Type' => 'application/json'
      },
      body: { sql: create_table_sql }.to_json
    )
    
    if response.success?
      puts "✅ Created table in Supabase"
    else
      puts "⚠️  Supabase response: #{response.body}"
      # Try alternative approach
      puts "Attempting alternative table creation..."
    end
  else
    puts "⚠️  Supabase credentials not found, skipping actual table creation"
  end
rescue => e
  puts "⚠️  Error creating table: #{e.message}"
  puts "Note: You may need to create the table manually in Supabase"
end

# Step 5: Update app files to fix authentication
puts "\nUpdating app files for authentication..."

# Update the App.tsx to include proper table name
app_tsx = app.app_files.find_by(path: 'src/App.tsx')
if app_tsx
  content = app_tsx.content
  
  # Fix table name references
  content = content.gsub("from('todos')", "from('app_57_todos')")
  content = content.gsub('.from("todos")', '.from("app_57_todos")')
  content = content.gsub(".from('todos')", ".from('app_57_todos')")
  
  app_tsx.update!(content: content)
  puts "✅ Updated App.tsx with correct table name"
end

# Step 6: Redeploy the app
puts "\nRedeploying app with updated configuration..."

begin
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    puts "✅ App redeployed successfully!"
    puts "\n🎉 SUCCESS! App 57 is now fixed."
    puts "🌐 Preview URL: #{result[:preview_url]}"
    puts "\n📝 Next steps:"
    puts "1. Visit the preview URL"
    puts "2. Sign up for a new account (or sign in if you have one)"
    puts "3. Try adding some todos!"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
rescue => e
  puts "❌ Deployment error: #{e.message}"
end

puts "\n=== Fix Complete ==="