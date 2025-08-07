#!/usr/bin/env ruby
# Fix OAuth redirect URL issues for app 69
# Run with: bin/rails runner scripts/fix_oauth_redirect.rb

puts "=" * 80
puts "🔧 FIXING OAUTH REDIRECT CONFIGURATION"
puts "=" * 80

app = App.find(69)
puts "\n📱 App ##{app.id}: #{app.name}"
puts "  Preview URL: #{app.preview_url}"

# Update the SocialButtons component to handle errors better
social_buttons_file = app.app_files.find_by(path: 'src/components/auth/SocialButtons.tsx')

if social_buttons_file
  puts "\n📝 Updating SocialButtons component with better error handling..."
  
  # Enhanced social buttons component with better error handling
  enhanced_content = <<~TSX
    import { useState } from 'react'
    import { supabase } from '../../lib/supabase'

    type Provider = 'google' | 'github'

    export function SocialButtons() {
      const [loading, setLoading] = useState<Provider | null>(null)
      const [error, setError] = useState<string | null>(null)

      const handleSocialLogin = async (provider: Provider) => {
        setLoading(provider)
        setError(null)
        
        try {
          // Get current URL to use as redirect
          const redirectTo = `${window.location.origin}/auth/callback`
          
          console.log(`Attempting ${provider} login with redirect: ${redirectTo}`)
          
          const { data, error } = await supabase.auth.signInWithOAuth({
            provider,
            options: {
              redirectTo,
              queryParams: {
                access_type: 'offline',
                prompt: 'consent',
              }
            }
          })

          if (error) {
            console.error(`${provider} OAuth error:`, error)
            
            // Handle specific OAuth errors
            if (error.message.includes('redirect')) {
              setError(`OAuth redirect not configured for ${provider}. Please contact support.`)
            } else if (error.message.includes('provider')) {
              setError(`${provider} provider is not properly configured. Please contact support.`)
            } else {
              setError(`${provider} login failed: ${error.message}`)
            }
          } else {
            console.log(`${provider} OAuth initiated successfully`)
            // User will be redirected, so no need to handle success here
          }
        } catch (err) {
          console.error(`Unexpected ${provider} login error:`, err)
          setError(`An unexpected error occurred with ${provider} login`)
        }
        
        setLoading(null)
      }

      return (
        <div className="space-y-3">
          {error && (
            <div className="bg-red-50 border border-red-200 rounded-md p-3 mb-4">
              <div className="text-red-700 text-sm">
                {error}
              </div>
              <button
                onClick={() => setError(null)}
                className="text-red-600 hover:text-red-800 text-xs mt-1 underline"
              >
                Dismiss
              </button>
            </div>
          )}
          
          <button
            type="button"
            onClick={() => handleSocialLogin('google')}
            disabled={loading === 'google'}
            className="w-full flex items-center justify-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading === 'google' ? (
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-gray-900 mr-2"></div>
            ) : (
              <svg className="w-4 h-4 mr-2" viewBox="0 0 24 24">
                <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
              </svg>
            )}
            {loading === 'google' ? 'Signing in...' : 'Continue with Google'}
          </button>

          <button
            type="button"
            onClick={() => handleSocialLogin('github')}
            disabled={loading === 'github'}
            className="w-full flex items-center justify-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {loading === 'github' ? (
              <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-gray-900 mr-2"></div>
            ) : (
              <svg className="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M10 0C4.477 0 0 4.484 0 10.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0110 4.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.203 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.942.359.31.678.921.678 1.856 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0020 10.017C20 4.484 15.522 0 10 0z" clipRule="evenodd" />
              </svg>
            )}
            {loading === 'github' ? 'Signing in...' : 'Continue with GitHub'}
          </button>
          
          <div className="text-center text-xs text-gray-500 mt-2">
            Having trouble? Try using email/password instead.
          </div>
        </div>
      )
    }
  TSX
  
  social_buttons_file.update!(content: enhanced_content)
  puts "✅ Updated SocialButtons with better error handling"
end

# Also update the AuthCallback to provide more detailed error information
auth_callback_file = app.app_files.find_by(path: 'src/pages/auth/AuthCallback.tsx')

if auth_callback_file
  puts "\n📝 Updating AuthCallback component with detailed error reporting..."
  
  enhanced_callback = <<~TSX
    import { useEffect, useState } from 'react'
    import { useNavigate, useSearchParams } from 'react-router-dom'
    import { supabase } from '../../lib/supabase'

    export function AuthCallback() {
      const navigate = useNavigate()
      const [searchParams] = useSearchParams()
      const [error, setError] = useState<string | null>(null)
      const [loading, setLoading] = useState(true)
      const [debugInfo, setDebugInfo] = useState<any>(null)

      useEffect(() => {
        const handleCallback = async () => {
          try {
            // Check for error in URL params first
            const errorParam = searchParams.get('error')
            const errorDescription = searchParams.get('error_description')
            
            if (errorParam) {
              console.error('OAuth error from URL:', { errorParam, errorDescription })
              
              let userFriendlyError = 'Authentication failed'
              
              if (errorParam === 'access_denied') {
                userFriendlyError = 'Access denied. You cancelled the authentication process.'
              } else if (errorParam === 'invalid_request') {
                userFriendlyError = 'Invalid authentication request. Please try again.'
              } else if (errorParam === 'server_error') {
                userFriendlyError = 'Server error during authentication. Please try again later.'
              } else if (errorDescription) {
                userFriendlyError = `Authentication error: ${errorDescription}`
              }
              
              setError(userFriendlyError)
              setDebugInfo({ errorParam, errorDescription, url: window.location.href })
              setLoading(false)
              return
            }

            // Try to exchange code for session
            const code = searchParams.get('code')
            if (code) {
              console.log('Exchanging code for session...')
              
              const { data, error } = await supabase.auth.exchangeCodeForSession(code)
              
              if (error) {
                console.error('Session exchange error:', error)
                setError(`Failed to complete authentication: ${error.message}`)
                setDebugInfo({ error, code: code.substring(0, 10) + '...', url: window.location.href })
              } else if (data.user) {
                console.log('Authentication successful:', data.user.email)
                navigate('/dashboard', { replace: true })
              } else {
                console.error('No user data received')
                setError('Authentication completed but no user data received')
                setDebugInfo({ data, url: window.location.href })
              }
            } else {
              console.error('No authorization code in URL')
              setError('No authorization code received from provider')
              setDebugInfo({ searchParams: Object.fromEntries(searchParams), url: window.location.href })
            }
          } catch (err) {
            console.error('Unexpected callback error:', err)
            setError(`Unexpected error: ${err instanceof Error ? err.message : 'Unknown error'}`)
            setDebugInfo({ err, url: window.location.href })
          }
          
          setLoading(false)
        }

        handleCallback()
      }, [navigate, searchParams])

      if (loading) {
        return (
          <div className="min-h-screen bg-gray-50 flex items-center justify-center">
            <div className="bg-white p-8 rounded-lg shadow-md max-w-md w-full text-center">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4"></div>
              <h2 className="text-xl font-semibold text-gray-900 mb-2">Completing Sign In</h2>
              <p className="text-gray-600">Please wait while we finish setting up your account...</p>
            </div>
          </div>
        )
      }

      if (error) {
        return (
          <div className="min-h-screen bg-gray-50 flex items-center justify-center">
            <div className="bg-white p-8 rounded-lg shadow-md max-w-md w-full">
              <div className="text-center mb-6">
                <div className="mx-auto flex items-center justify-center h-12 w-12 rounded-full bg-red-100 mb-4">
                  <svg className="h-6 w-6 text-red-600" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-2.5L13.732 4c-.77-.833-1.964-.833-2.732 0L4.732 15.5c-.77.833.192 2.5 1.732 2.5z" />
                  </svg>
                </div>
                <h2 className="text-xl font-semibold text-gray-900 mb-2">Authentication Failed</h2>
                <p className="text-gray-600 mb-4">{error}</p>
                
                <div className="flex flex-col space-y-2">
                  <button
                    onClick={() => navigate('/login')}
                    className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                  >
                    Try Again
                  </button>
                  
                  <button
                    onClick={() => navigate('/signup')}
                    className="text-blue-600 hover:text-blue-800 text-sm"
                  >
                    Create Account Instead
                  </button>
                </div>
                
                {debugInfo && (
                  <details className="mt-4 text-left">
                    <summary className="text-xs text-gray-500 cursor-pointer hover:text-gray-700">
                      Technical Details
                    </summary>
                    <pre className="mt-2 text-xs text-gray-600 bg-gray-50 p-2 rounded overflow-auto">
                      {JSON.stringify(debugInfo, null, 2)}
                    </pre>
                  </details>
                )}
              </div>
            </div>
          </div>
        )
      }

      return null
    }
  TSX
  
  auth_callback_file.update!(content: enhanced_callback)
  puts "✅ Updated AuthCallback with detailed error reporting"
end

# Redeploy the app
puts "\n🚀 Redeploying app with fixes..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  
  puts "\n📋 Test the fixes:"
  puts "  1. Visit: #{result[:preview_url]}/login"
  puts "  2. Try social login (will show detailed errors now)"
  puts "  3. Check browser console for detailed logs"
  puts "  4. OAuth errors will be more user-friendly"
  
  puts "\n🔧 If OAuth still fails, add to Supabase dashboard:"
  puts "  Redirect URL: #{result[:preview_url]}/auth/callback"
  puts "  Or use wildcard: https://preview-*.overskill.app/auth/callback"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n" + "=" * 80
puts "OAuth fix deployment complete"
puts "=" * 80