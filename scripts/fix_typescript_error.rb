#!/usr/bin/env ruby
# Fix TypeScript error in SocialButtons
app = App.find(69)
social_file = app.app_files.find_by(path: 'src/components/auth/SocialButtons.tsx')
content = social_file.content
# Remove the unused 'data' variable
fixed = content.gsub('const { data, error } = await supabase.auth.signInWithOAuth({', 'const { error } = await supabase.auth.signInWithOAuth({')
social_file.update!(content: fixed)
puts 'Fixed unused variable in SocialButtons'