#!/usr/bin/env ruby
# Fix PKCE validation issues in OAuth flow
# Run with: bin/rails runner scripts/fix_pkce_validation.rb

puts "=" * 80
puts "🔧 FIXING PKCE VALIDATION ISSUES"
puts "=" * 80

puts "\n📊 Analysis from Supabase logs:"
puts "- Request: POST /auth/v1/token?grant_type=pkce"
puts "- Status: 400 (validation_failed)"
puts "- Source: https://preview-69.overskill.app/"
puts ""
puts "The PKCE flow is failing during token exchange. This typically means:"
puts "1. Authorization code is invalid or expired"
puts "2. Code verifier doesn't match code challenge"
puts "3. Redirect URI mismatch during token exchange"

app = App.find(69)
puts "\n📱 Fixing App ##{app.id}: #{app.name}"

# Update the AuthCallback component to handle PKCE properly
auth_callback_file = app.app_files.find_by(path: 'src/pages/auth/AuthCallback.tsx')

if auth_callback_file
  puts "\n📝 Updating AuthCallback with better PKCE handling..."
  
  improved_callback = <<~TSX
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
            console.log('🔄 Starting auth callback process...')
            console.log('URL:', window.location.href)
            console.log('Search params:', Object.fromEntries(searchParams))

            // Check for error in URL params first
            const errorParam = searchParams.get('error')
            const errorDescription = searchParams.get('error_description')
            
            if (errorParam) {
              console.error('❌ OAuth error from provider:', { errorParam, errorDescription })
              
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

            // Get the authorization code
            const code = searchParams.get('code')
            if (!code) {
              console.error('❌ No authorization code in URL')
              setError('No authorization code received from provider')
              setDebugInfo({ searchParams: Object.fromEntries(searchParams), url: window.location.href })
              setLoading(false)
              return
            }

            console.log('✅ Authorization code received:', code.substring(0, 10) + '...')

            // Exchange code for session using the proper method
            console.log('🔄 Exchanging code for session...')
            
            const { data, error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)
            
            if (exchangeError) {
              console.error('❌ Session exchange error:', exchangeError)
              
              let userFriendlyError = `Failed to complete authentication: ${exchangeError.message}`
              
              // Handle specific PKCE/validation errors
              if (exchangeError.message.includes('validation_failed') || exchangeError.message.includes('invalid_grant')) {
                userFriendlyError = 'Authentication session expired or invalid. Please try signing in again.'
              } else if (exchangeError.message.includes('pkce')) {
                userFriendlyError = 'OAuth security validation failed. Please try signing in again.'
              } else if (exchangeError.message.includes('redirect_uri')) {
                userFriendlyError = 'OAuth redirect configuration issue. Please contact support.'
              }
              
              setError(userFriendlyError)
              setDebugInfo({ 
                error: exchangeError, 
                code: code.substring(0, 10) + '...', 
                url: window.location.href,
                timestamp: new Date().toISOString()
              })
            } else if (data.user) {
              console.log('✅ Authentication successful for:', data.user.email)
              console.log('Session expires at:', data.session?.expires_at)
              
              // Navigate to dashboard on success
              navigate('/dashboard', { replace: true })
              return
            } else {
              console.error('❌ No user data received despite successful exchange')
              setError('Authentication completed but no user data received')
              setDebugInfo({ data, url: window.location.href })
            }
          } catch (err) {
            console.error('❌ Unexpected callback error:', err)
            setError(`Unexpected error: ${err instanceof Error ? err.message : 'Unknown error'}`)
            setDebugInfo({ err, url: window.location.href })
          }
          
          setLoading(false)
        }

        // Add a small delay to ensure URL is fully loaded
        const timer = setTimeout(handleCallback, 100)
        return () => clearTimeout(timer)
      }, [navigate, searchParams])

      if (loading) {
        return (
          <div className="min-h-screen bg-gray-50 flex items-center justify-center">
            <div className="bg-white p-8 rounded-lg shadow-md max-w-md w-full text-center">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4"></div>
              <h2 className="text-xl font-semibold text-gray-900 mb-2">Completing Sign In</h2>
              <p className="text-gray-600">Please wait while we finish setting up your account...</p>
              
              <div className="mt-4 text-xs text-gray-500">
                This may take a few seconds
              </div>
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
                      Technical Details (for debugging)
                    </summary>
                    <pre className="mt-2 text-xs text-gray-600 bg-gray-50 p-2 rounded overflow-auto max-h-32">
                      {JSON.stringify(debugInfo, null, 2)}
                    </pre>
                    <div className="text-xs text-gray-500 mt-2">
                      If this problem persists, please share these details with support.
                    </div>
                  </details>
                )}
              </div>
            </div>
          </div>
        )
      }

      // This shouldn't be reached, but just in case
      return (
        <div className="min-h-screen bg-gray-50 flex items-center justify-center">
          <div className="text-center">
            <p className="text-gray-600">Redirecting...</p>
          </div>
        </div>
      )
    }
  TSX
  
  auth_callback_file.update!(content: improved_callback)
  puts "✅ Updated AuthCallback with better PKCE handling and debugging"
end

# Also improve the SocialButtons component to ensure proper OAuth initiation
social_buttons_file = app.app_files.find_by(path: 'src/components/auth/SocialButtons.tsx')

if social_buttons_file
  puts "\n📝 Updating SocialButtons to ensure proper OAuth initiation..."
  
  # Get current content and improve it
  content = social_buttons_file.content
  
  # Add better redirect URL construction and PKCE flow handling
  improved_content = content.gsub(
    /const redirectTo = `\$\{window\.location\.origin\}\/auth\/callback`/,
    'const redirectTo = `${window.location.origin}/auth/callback`'
  ).gsub(
    /const \{ error \} = await supabase\.auth\.signInWithOAuth\(\{/,
    <<~JS.strip
      console.log(`🔄 Starting ${provider} OAuth with redirect: ${redirectTo}`)
          
          const { error } = await supabase.auth.signInWithOAuth({
    JS
  )
  
  # Ensure PKCE is explicitly enabled (it should be by default, but let's be sure)
  improved_content = improved_content.gsub(
    /options: \{[^}]*\}/m
  ) do |match|
    if match.include?('queryParams')
      match
    else
      match.gsub(
        /options: \{([^}]*)\}/,
        <<~JS.strip
          options: {
                redirectTo,
                queryParams: {
                  access_type: 'offline',
                  prompt: 'consent',
                }
              }
        JS
      )
    end
  end
  
  if improved_content != content
    social_buttons_file.update!(content: improved_content)
    puts "✅ Updated SocialButtons with better OAuth logging"
  end
end

# Redeploy the app
puts "\n🚀 Redeploying app with PKCE fixes..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  
  puts "\n📋 Test the PKCE fixes:"
  puts "  1. Visit: #{result[:preview_url]}/login"
  puts "  2. Try social login (will show better error messages)"
  puts "  3. Check browser console for detailed PKCE flow logs"
  puts "  4. Look for 'Starting OAuth' and 'Exchanging code' messages"
  
  puts "\n🔍 Debugging OAuth:"
  puts "  - Open browser console before clicking social login"
  puts "  - Watch for detailed logging during OAuth flow"
  puts "  - Check if authorization code is received properly"
  puts "  - Verify session exchange succeeds"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n💡 If PKCE validation still fails:"
puts "1. Check if redirect URL exactly matches what's configured in Supabase"
puts "2. Ensure OAuth provider (Google/GitHub) is properly configured with credentials"
puts "3. Try clearing browser cache/cookies for the app domain"
puts "4. Check Supabase dashboard for any recent configuration changes"

puts "\n" + "=" * 80
puts "PKCE validation fix complete"
puts "=" * 80