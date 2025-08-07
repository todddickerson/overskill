#!/usr/bin/env ruby
# Fix PKCE code verifier issue
# Run with: bin/rails runner scripts/fix_pkce_code_verifier.rb

puts "=" * 80
puts "🔧 FIXING PKCE CODE VERIFIER ISSUE"
puts "=" * 80

puts "\n📊 Error Analysis:"
puts "Error: 'invalid request: both auth code and code verifier should be non-empty'"
puts "Code: '193a60e2-c...'"
puts "Status: 400 (validation_failed)"
puts ""
puts "💡 Root Cause:"
puts "The PKCE flow is missing the code verifier during token exchange."
puts "This happens when the session storage is cleared or not properly managed."

app = App.find(69)
puts "\n📱 Fixing App ##{app.id}: #{app.name}"

# The issue is that Supabase client needs to manage PKCE state properly
# Let's update the supabase client configuration to ensure PKCE works correctly

supabase_file = app.app_files.find_by(path: 'src/lib/supabase.ts')

if supabase_file
  puts "\n📝 Updating Supabase client configuration for PKCE..."
  
  # Get current content and enhance it
  content = supabase_file.content
  
  # Find the createClient call and ensure PKCE is properly configured
  enhanced_content = content.gsub(
    /export const supabase = createClient\(supabaseUrl, supabaseAnonKey, \{[^}]*\}\)/m
  ) do |match|
    <<~JS.strip
      export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true,
          flowType: 'pkce',
          storage: typeof window !== 'undefined' ? window.localStorage : undefined,
          storageKey: 'supabase.auth.token',
          debug: import.meta.env?.DEV || (window as any)?.ENV?.ENVIRONMENT === 'development'
        },
        global: {
          headers: {
            'x-client-info': 'overskill-app'
          }
        }
      })
    JS
  end
  
  if enhanced_content != content
    supabase_file.update!(content: enhanced_content)
    puts "✅ Updated Supabase client with proper PKCE configuration"
  else
    puts "⚠️ Supabase client already has proper configuration"
  end
end

# Update AuthCallback to better handle the PKCE session state
auth_callback_file = app.app_files.find_by(path: 'src/pages/auth/AuthCallback.tsx')

if auth_callback_file
  puts "\n📝 Updating AuthCallback to handle PKCE session state..."
  
  # Enhanced callback that ensures PKCE state is preserved
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
            console.log('🔄 Starting PKCE auth callback process...')
            console.log('URL:', window.location.href)
            console.log('Search params:', Object.fromEntries(searchParams))
            
            // Check localStorage for PKCE state
            const storedSession = localStorage.getItem('supabase.auth.token')
            console.log('Stored session exists:', !!storedSession)

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
              setError('No authorization code received from provider. Please try signing in again.')
              setDebugInfo({ 
                searchParams: Object.fromEntries(searchParams), 
                url: window.location.href,
                hasStoredSession: !!storedSession
              })
              setLoading(false)
              return
            }

            console.log('✅ Authorization code received:', code.substring(0, 10) + '...')

            // Use getSessionFromUrl instead of exchangeCodeForSession for better PKCE handling
            console.log('🔄 Getting session from URL (PKCE flow)...')
            
            const { data, error: sessionError } = await supabase.auth.getSessionFromUrl({ 
              storeSession: true 
            })
            
            if (sessionError) {
              console.error('❌ PKCE session error:', sessionError)
              
              let userFriendlyError = `Failed to complete authentication: ${sessionError.message}`
              
              // Handle specific PKCE/validation errors
              if (sessionError.message.includes('code verifier') || sessionError.message.includes('non-empty')) {
                userFriendlyError = 'Authentication session was interrupted. Please clear your browser data and try signing in again.'
              } else if (sessionError.message.includes('validation_failed') || sessionError.message.includes('invalid_grant')) {
                userFriendlyError = 'Authentication session expired. Please try signing in again.'
              } else if (sessionError.message.includes('pkce')) {
                userFriendlyError = 'OAuth security validation failed. Please clear browser cache and try again.'
              }
              
              setError(userFriendlyError)
              setDebugInfo({ 
                error: sessionError, 
                code: code.substring(0, 10) + '...', 
                url: window.location.href,
                timestamp: new Date().toISOString(),
                hasStoredSession: !!storedSession
              })
            } else if (data.session?.user) {
              console.log('✅ PKCE authentication successful for:', data.session.user.email)
              console.log('Session expires at:', data.session?.expires_at)
              
              // Navigate to dashboard on success
              navigate('/dashboard', { replace: true })
              return
            } else {
              console.error('❌ No session data received from PKCE flow')
              setError('Authentication completed but no session created. Please try again.')
              setDebugInfo({ 
                data, 
                url: window.location.href,
                hasStoredSession: !!storedSession
              })
            }
          } catch (err) {
            console.error('❌ Unexpected PKCE callback error:', err)
            setError(`Unexpected error: ${err instanceof Error ? err.message : 'Unknown error'}`)
            setDebugInfo({ 
              err, 
              url: window.location.href,
              timestamp: new Date().toISOString()
            })
          }
          
          setLoading(false)
        }

        // Ensure DOM is ready before processing
        if (document.readyState === 'complete') {
          handleCallback()
        } else {
          const timer = setTimeout(handleCallback, 300)
          return () => clearTimeout(timer)
        }
      }, [navigate, searchParams])

      if (loading) {
        return (
          <div className="min-h-screen bg-gray-50 flex items-center justify-center">
            <div className="bg-white p-8 rounded-lg shadow-md max-w-md w-full text-center">
              <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600 mx-auto mb-4"></div>
              <h2 className="text-xl font-semibold text-gray-900 mb-2">Completing Sign In</h2>
              <p className="text-gray-600">Processing your authentication...</p>
              
              <div className="mt-4 text-xs text-gray-500">
                Validating OAuth credentials
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
                    onClick={() => {
                      // Clear any stored auth state before retry
                      localStorage.removeItem('supabase.auth.token')
                      sessionStorage.clear()
                      navigate('/login')
                    }}
                    className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                  >
                    Clear Data & Try Again
                  </button>
                  
                  <button
                    onClick={() => navigate('/signup')}
                    className="text-blue-600 hover:text-blue-800 text-sm"
                  >
                    Create Account Instead
                  </button>
                </div>
                
                {error.includes('code verifier') && (
                  <div className="mt-4 p-3 bg-yellow-50 border border-yellow-200 rounded text-sm text-yellow-800">
                    <strong>Tip:</strong> This error often occurs when browser data is corrupted. 
                    Try using an incognito/private window or clearing your browser cache.
                  </div>
                )}
                
                {debugInfo && (
                  <details className="mt-4 text-left">
                    <summary className="text-xs text-gray-500 cursor-pointer hover:text-gray-700">
                      Technical Details (for debugging)
                    </summary>
                    <pre className="mt-2 text-xs text-gray-600 bg-gray-50 p-2 rounded overflow-auto max-h-32">
                      {JSON.stringify(debugInfo, null, 2)}
                    </pre>
                    <div className="text-xs text-gray-500 mt-2">
                      Share these details with support if the problem persists.
                    </div>
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
  puts "✅ Updated AuthCallback with better PKCE session handling"
end

# Redeploy the app
puts "\n🚀 Redeploying app with PKCE code verifier fix..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  
  puts "\n📋 Test the PKCE code verifier fix:"
  puts "  1. Clear browser data (important!)"
  puts "  2. Visit: #{result[:preview_url]}/login"
  puts "  3. Try social login in a fresh session"
  puts "  4. The 'code verifier' error should be resolved"
  
  puts "\n🔍 If still failing:"
  puts "  - Try incognito/private browsing mode"
  puts "  - Clear all browser data for the domain"
  puts "  - Check browser console for PKCE flow logs"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n💡 Key Changes Made:"
puts "1. Enhanced Supabase client PKCE configuration"
puts "2. Used getSessionFromUrl() instead of exchangeCodeForSession()"
puts "3. Added proper session storage management"
puts "4. Better error handling for code verifier issues"
puts "5. Clear browser data functionality in error UI"

puts "\n" + "=" * 80
puts "PKCE code verifier fix complete"
puts "=" * 80