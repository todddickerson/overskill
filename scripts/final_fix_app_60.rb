#!/usr/bin/env ruby
# Final fix for app 60 SignUp.tsx
# Run with: bin/rails runner scripts/final_fix_app_60.rb

app = App.find(60)
signup_file = app.app_files.find_by(path: 'src/pages/auth/SignUp.tsx')

if signup_file
  content = signup_file.content
  # Remove useNavigate from import if it exists
  fixed = content.gsub(/import { Link, useNavigate } from 'react-router-dom'/, "import { Link } from 'react-router-dom'")
  # Also remove the commented line if it exists
  fixed = fixed.gsub(/\/\/ const navigate = useNavigate\(\).*\n/, '')
  
  signup_file.update!(content: fixed)
  puts "✅ Fixed SignUp.tsx - removed unused useNavigate import"
else
  puts "❌ SignUp.tsx not found"
end

puts "\nReady to deploy! Run: bin/rails runner scripts/test_app_60_auth.rb"