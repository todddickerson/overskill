#!/usr/bin/env ruby
# Fix TypeScript types in Auth component
# Run with: bin/rails runner scripts/fix_auth_types.rb

app = App.find(57)
auth_file = app.app_files.find_by(path: "src/components/Auth.tsx")

if auth_file
  auth_content = <<~TSX
import { useState } from 'react'
import { supabase } from '../lib/supabase'

interface AuthProps {
  onAuth: (user: any) => void
}

export function Auth({ onAuth }: AuthProps) {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [loading, setLoading] = useState(false)
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    
    try {
      if (mode === 'signup') {
        const { error } = await supabase.auth.signUp({
          email,
          password
        })
        if (error) throw error
        alert('Check your email for confirmation!')
      } else {
        const { data, error } = await supabase.auth.signInWithPassword({
          email,
          password
        })
        if (error) throw error
        if (data.user) onAuth(data.user)
      }
    } catch (error: any) {
      alert(error.message || 'An error occurred')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="max-w-md w-full space-y-8 p-8 bg-white rounded-lg shadow">
        <h2 className="text-center text-3xl font-extrabold text-gray-900">
          {mode === 'signin' ? 'Sign in' : 'Create account'}
        </h2>
        <form className="mt-8 space-y-6" onSubmit={handleSubmit}>
          <div className="space-y-4">
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              placeholder="Email address"
            />
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              placeholder="Password"
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full py-2 px-4 bg-indigo-600 text-white rounded-md hover:bg-indigo-700 disabled:opacity-50"
          >
            {loading ? 'Loading...' : (mode === 'signin' ? 'Sign in' : 'Sign up')}
          </button>
          <button
            type="button"
            onClick={() => setMode(mode === 'signin' ? 'signup' : 'signin')}
            className="w-full text-center text-indigo-600 hover:text-indigo-500"
          >
            {mode === 'signin' ? "Need an account? Sign up" : 'Have an account? Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
TSX

  auth_file.update!(content: auth_content)
  puts "✅ Updated Auth.tsx with proper TypeScript types"
  
  # Deploy again
  puts "Deploying..."
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    app.update!(
      status: 'published',
      preview_url: result[:preview_url],
      deployed_at: Time.current
    )
    puts "✅ Deployment successful!"
    puts "  Preview URL: #{result[:preview_url]}"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
else
  puts "❌ Auth.tsx not found"
end