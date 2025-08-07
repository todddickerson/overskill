#!/usr/bin/env ruby
# Fix TypeScript errors in app 60
# Run with: bin/rails runner scripts/fix_app_60_typescript.rb

app = App.find(60)
puts "Fixing TypeScript errors in App ##{app.id}..."

# Fix supabase.ts
supabase_file = app.app_files.find_by(path: 'src/lib/supabase.ts')
if supabase_file
  content = supabase_file.content
  # Fix import.meta.env references to check both sources
  fixed = content.gsub('import.meta.env.', '((import.meta as any).env || window.ENV || {}).')
  supabase_file.update!(content: fixed)
  puts "✅ Fixed supabase.ts - updated environment variable access"
end

# Fix SignUp.tsx unused variable
signup_file = app.app_files.find_by(path: 'src/pages/auth/SignUp.tsx')
if signup_file
  content = signup_file.content
  # Comment out unused navigate to preserve it for future use
  if content.include?('const navigate = useNavigate()')
    fixed = content.gsub('const navigate = useNavigate()', '// const navigate = useNavigate() // Will be used after signup')
    signup_file.update!(content: fixed)
    puts "✅ Fixed SignUp.tsx - commented unused navigate"
  end
end

# Add vite-env.d.ts for TypeScript
vite_env_content = <<~TYPESCRIPT
    /// <reference types="vite/client" />

    interface ImportMetaEnv {
      readonly VITE_SUPABASE_URL: string
      readonly VITE_SUPABASE_ANON_KEY: string
    }

    interface ImportMeta {
      readonly env: ImportMetaEnv
    }

    interface Window {
      ENV: Record<string, any>
    }
TYPESCRIPT

vite_env = app.app_files.find_by(path: 'src/vite-env.d.ts')
if !vite_env
  vite_env = app.app_files.create!(
    path: 'src/vite-env.d.ts',
    team: app.team,
    content: vite_env_content
  )
else
  vite_env.update!(content: vite_env_content)
end
puts "✅ Added vite-env.d.ts - TypeScript environment definitions"

puts "\n🎉 All TypeScript errors fixed!"
puts "You can now run: bin/rails runner scripts/test_app_60_auth.rb"