#!/usr/bin/env ruby
# Fix App 61 Supabase environment variables
# Run with: bin/rails runner scripts/fix_app_61_supabase.rb

app = App.find(61)
puts "Fixing App ##{app.id}: #{app.name}"

supabase_file = app.app_files.find_by(path: 'src/lib/supabase.ts')
if supabase_file
  new_content = <<~TSX
    import { createClient } from '@supabase/supabase-js'
    
    // Support both build-time (import.meta.env) and runtime (window.ENV) environments
    const supabaseUrl = 
      (import.meta as any).env?.VITE_SUPABASE_URL || 
      (window as any).ENV?.SUPABASE_URL || 
      ''
    
    const supabaseAnonKey = 
      (import.meta as any).env?.VITE_SUPABASE_ANON_KEY || 
      (window as any).ENV?.SUPABASE_ANON_KEY || 
      ''
    
    if (!supabaseUrl || !supabaseAnonKey) {
      console.warn('Supabase credentials not found. Authentication features will not work.')
    }
    
    export const supabase = createClient(supabaseUrl, supabaseAnonKey)
  TSX
  
  supabase_file.update!(content: new_content)
  puts "✅ Updated supabase.ts"
  
  # Redeploy
  puts "Redeploying..."
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    puts "✅ Redeployed with fix"
    puts "URL: #{result[:preview_url]}"
  else
    puts "❌ Deploy failed: #{result[:error]}"
  end
else
  puts "❌ supabase.ts not found"
end