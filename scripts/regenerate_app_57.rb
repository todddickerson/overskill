#!/usr/bin/env ruby
# Regenerate App 57 with proper authentication and database support
# Run with: bin/rails runner scripts/regenerate_app_57.rb

puts "=== Regenerating App 57 with Authentication ==="

app = App.find(57)
puts "App: #{app.name} (ID: #{app.id})"
puts "Current status: #{app.status}"

# Step 1: Ensure database entities are created
puts "\n1. Setting up database entities..."
unless app.database_shard
  app.database_shard = DatabaseShard.first || DatabaseShard.create!(
    name: 'default-shard',
    shard_number: 1,
    supabase_project_id: 'overskill-default',
    supabase_url: ENV['SUPABASE_URL'],
    supabase_anon_key: ENV['SUPABASE_ANON_KEY'],
    supabase_service_key: ENV['SUPABASE_SERVICE_KEY'],
    app_count: 0,
    status: 'available'
  )
  app.save!
end

# Create todos table entity
todos_table = app.app_tables.find_or_create_by!(name: 'todos') do |t|
  t.team = app.team
  t.display_name = 'Todos'
  t.scope_type = 'user_scoped'
end

# Add columns
if todos_table.app_table_columns.empty?
  todos_table.app_table_columns.create!([
    { name: 'id', column_type: 'uuid', is_primary: true },
    { name: 'user_id', column_type: 'uuid', is_foreign_key: true, foreign_table: 'auth.users' },
    { name: 'text', column_type: 'text', is_required: true },
    { name: 'completed', column_type: 'boolean', default_value: 'false' },
    { name: 'created_at', column_type: 'timestamp', default_value: 'now()' },
    { name: 'updated_at', column_type: 'timestamp', default_value: 'now()' }
  ])
end

puts "✅ Database entities created"
puts "  - Shard: #{app.database_shard.name}"
puts "  - Table: #{todos_table.name} (#{todos_table.app_table_columns.count} columns)"

# Step 2: Create a new chat message to trigger regeneration
puts "\n2. Creating regeneration request..."
creator = app.creator || app.team.memberships.first

# Enhanced prompt that emphasizes authentication
regeneration_prompt = <<~PROMPT
Please regenerate this todo app with the following requirements:

1. **Authentication is MANDATORY** - The app MUST have user login/signup functionality
2. Use the existing database table: app_#{app.id}_todos
3. Include these features:
   - User authentication (login/signup) using Supabase Auth
   - Only show todos for the logged-in user
   - Add/edit/delete todos with real-time updates
   - Clean, modern UI with Tailwind CSS
   - Proper error handling

IMPORTANT: 
- Create an Auth.jsx component for login/signup
- Check authentication state in App.tsx
- All database queries MUST include user_id filtering
- Use table name: app_#{app.id}_todos (not just 'todos')

Make it a professional, production-ready todo app with authentication.
PROMPT

chat_message = app.app_chat_messages.create!(
  user: creator.user,
  membership: creator,
  content: regeneration_prompt,
  processing_status: 'pending',
  metadata: {
    regeneration: true,
    force_auth: true,
    table_name: "app_#{app.id}_todos"
  }
)

puts "✅ Created chat message ##{chat_message.id}"

# Step 3: Process the message with the new orchestrator
puts "\n3. Processing with AI orchestrator..."
begin
  # Use the V2 orchestrator with enhanced capabilities
  orchestrator = Ai::AppUpdateOrchestratorV2.new(chat_message)
  
  # Set app to generating status
  app.update!(status: 'generating')
  
  # Execute the orchestration
  result = orchestrator.execute!
  
  if result[:success]
    puts "✅ AI generation completed successfully!"
    puts "  Files created/updated: #{result[:files_updated]}" if result[:files_updated]
    
    # Mark message as processed
    chat_message.update!(
      processing_status: 'completed',
      ai_response: result[:response],
      processing_completed_at: Time.current
    )
    
    # Update app status
    app.update!(status: 'generated')
  else
    puts "❌ AI generation failed: #{result[:error]}"
    chat_message.update!(
      processing_status: 'failed',
      error_message: result[:error]
    )
    app.update!(status: 'failed')
  end
rescue => e
  puts "❌ Error during orchestration: #{e.message}"
  puts e.backtrace.first(5).join("\n") if Rails.env.development?
  
  chat_message.update!(
    processing_status: 'failed',
    error_message: e.message
  )
  app.update!(status: 'failed')
end

# Step 4: Deploy the app
if app.generated?
  puts "\n4. Deploying to Cloudflare..."
  begin
    deploy_service = Deployment::CloudflarePreviewService.new(app)
    deploy_result = deploy_service.update_preview!
    
    if deploy_result[:success]
      puts "✅ Deployment successful!"
      puts "  Preview URL: #{deploy_result[:preview_url]}"
      app.update!(
        status: 'published',
        preview_url: deploy_result[:preview_url],
        deployed_at: Time.current
      )
    else
      puts "❌ Deployment failed: #{deploy_result[:error]}"
    end
  rescue => e
    puts "❌ Deployment error: #{e.message}"
  end
end

# Step 5: Output the SQL for manual table creation
puts "\n5. Database Setup"
puts "=" * 60
puts "The following SQL needs to be executed in Supabase:"
puts "=" * 60

table_sql = <<~SQL
-- Create the todos table for App #{app.id}
CREATE TABLE IF NOT EXISTS app_#{app.id}_todos (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  text TEXT NOT NULL,
  completed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_app_#{app.id}_todos_user_id 
  ON app_#{app.id}_todos(user_id);
CREATE INDEX IF NOT EXISTS idx_app_#{app.id}_todos_created_at 
  ON app_#{app.id}_todos(created_at DESC);

-- Enable RLS
ALTER TABLE app_#{app.id}_todos ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own todos"
  ON app_#{app.id}_todos FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own todos"
  ON app_#{app.id}_todos FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own todos"
  ON app_#{app.id}_todos FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own todos"
  ON app_#{app.id}_todos FOR DELETE
  USING (auth.uid() = user_id);

-- Grant permissions
GRANT ALL ON app_#{app.id}_todos TO authenticated;
GRANT ALL ON app_#{app.id}_todos TO service_role;
SQL

puts table_sql

# Save SQL to file
sql_file = Rails.root.join('tmp', "app_#{app.id}_create_tables.sql")
File.write(sql_file, table_sql)
puts "\n✅ SQL saved to: #{sql_file}"

# Final summary
puts "\n" + "=" * 60
puts "REGENERATION SUMMARY"
puts "=" * 60
puts "App ID: #{app.id}"
puts "App Name: #{app.name}"
puts "Status: #{app.status}"
puts "Tables: #{app.app_tables.pluck(:name).join(', ')}"
puts "Files: #{app.app_files.count}"
puts "Preview URL: #{app.preview_url || app.published_url}"
puts ""
puts "Next Steps:"
puts "1. Execute the SQL above in Supabase dashboard"
puts "2. Test authentication at: #{app.preview_url || app.published_url}"
puts "3. Verify todos are user-scoped"
puts "=" * 60