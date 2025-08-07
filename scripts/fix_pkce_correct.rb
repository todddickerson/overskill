#!/usr/bin/env ruby
# Fix PKCE code verifier issue with correct Supabase methods
# Run with: bin/rails runner scripts/fix_pkce_correct.rb

puts "=" * 80
puts "🔧 FIXING PKCE ISSUE WITH CORRECT SUPABASE METHODS"
puts "=" * 80

puts "\n📊 Error Analysis:"
puts "Error: 'invalid request: both auth code and code verifier should be non-empty'"
puts "Issue: getSessionFromUrl() doesn't exist in current Supabase client"
puts "Fix: Use exchangeCodeForSession() with proper error handling"

app = App.find(69)
puts "\n📱 Fixing App ##{app.id}: #{app.name}"

# Update the AuthCallback component with correct PKCE handling
auth_callback_file = app.app_files.find_by(path: 'src/pages/auth/AuthCallback.tsx')

if auth_callback_file
  puts "\n📝 Updating AuthCallback with correct PKCE methods..."
  
  corrected_callback = <<~TSX
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
            console.log('🔄 Starting PKCE auth callback...')
            console.log('Full URL:', window.location.href)
            console.log('Search params:', Object.fromEntries(searchParams))
            
            // Check localStorage for any stored auth state
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

            // Handle PKCE session - Supabase should auto-detect and process
            console.log('🔄 Processing PKCE session...')
            
            // First, check if there's already a session from the OAuth flow
            const { data: { session: currentSession } } = await supabase.auth.getSession()
            
            if (currentSession?.user) {
              console.log('✅ Session already established:', currentSession.user.email)
              navigate('/dashboard', { replace: true })
              return
            }
            
            // If no session yet, the OAuth callback should have already been processed
            // Let's try to refresh/get the session again after a short delay
            console.log('🔄 Waiting for session to be established...')
            await new Promise(resolve => setTimeout(resolve, 1000))
            
            const { data: { session: refreshedSession } } = await supabase.auth.getSession()
            
            if (refreshedSession?.user) {
              console.log('✅ Session established after refresh:', refreshedSession.user.email)
              navigate('/dashboard', { replace: true })
              return
            }
            
            // If still no session, try manual code exchange
            console.log('🔄 Attempting manual code exchange...')
            const { data, error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)
            
            if (exchangeError) {
              console.error('❌ PKCE exchange error:', exchangeError)
              
              let userFriendlyError = `Failed to complete authentication: ${exchangeError.message}`
              
              // Handle specific PKCE/validation errors
              if (exchangeError.message.includes('code verifier') || exchangeError.message.includes('non-empty')) {
                userFriendlyError = 'OAuth validation failed. This may be due to browser storage issues. Please try:'
                userFriendlyError += '\\n\\n1. Clear your browser data for this site'
                userFriendlyError += '\\n2. Try using an incognito/private window'
                userFriendlyError += '\\n3. Disable browser extensions temporarily'
              } else if (exchangeError.message.includes('validation_failed') || exchangeError.message.includes('invalid_grant')) {
                userFriendlyError = 'Authentication session expired or invalid. The login process was interrupted. Please try signing in again.'
              } else if (exchangeError.message.includes('pkce') || exchangeError.message.includes('PKCE')) {
                userFriendlyError = 'OAuth security validation failed. This typically happens when the login session is corrupted.'
              }
              
              setError(userFriendlyError)
              setDebugInfo({ 
                error: exchangeError, 
                code: code.substring(0, 10) + '...', 
                url: window.location.href,
                timestamp: new Date().toISOString(),
                hasStoredSession: !!storedSession,
                userAgent: navigator.userAgent
              })
            } else if (data.session?.user) {
              console.log('✅ Manual exchange successful:', data.session.user.email)
              console.log('Session expires at:', data.session?.expires_at)
              
              // Navigate to dashboard on success
              navigate('/dashboard', { replace: true })
              return
            } else {
              console.error('❌ No session data from manual exchange')
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
              timestamp: new Date().toISOString(),
              stack: err instanceof Error ? err.stack : null
            })
          }
          
          setLoading(false)
        }

        // Ensure DOM is ready and URL params are parsed
        if (document.readyState === 'complete') {
          handleCallback()
        } else {
          const timer = setTimeout(handleCallback, 500)
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
                Validating OAuth credentials and establishing session
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
                <div className="text-gray-600 mb-4 whitespace-pre-line text-sm">
                  {error}
                </div>
                
                <div className="flex flex-col space-y-2">
                  <button
                    onClick={() => {
                      // Clear any stored auth state before retry
                      localStorage.removeItem('supabase.auth.token')
                      sessionStorage.clear()
                      // Clear cookies for this domain
                      document.cookie.split(";").forEach(c => {
                        document.cookie = c.replace(/^ +/, "").replace(/=.*/, "=;expires=" + new Date().toUTCString() + ";path=/");
                      })
                      navigate('/login')
                    }}
                    className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                  >
                    Clear Data & Try Again
                  </button>
                  
                  <button
                    onClick={() => window.open(window.location.origin + '/login', '_blank')}
                    className="bg-green-600 text-white px-4 py-2 rounded hover:bg-green-700"
                  >
                    Try in New Window
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
                    Try using an incognito/private window or a different browser.
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
  
  auth_callback_file.update!(content: corrected_callback)
  puts "✅ Updated AuthCallback with correct PKCE handling"
end

# Redeploy the app
puts "\n🚀 Redeploying app with corrected PKCE fix..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  
  puts "\n📋 Test the corrected PKCE fix:"
  puts "  1. Clear browser data (important!)"
  puts "  2. Visit: #{result[:preview_url]}/login"
  puts "  3. Try social login - now uses proper exchangeCodeForSession()"
  puts "  4. Check console for detailed PKCE flow logging"
  
  puts "\n🔍 If authentication still fails:"
  puts "  - The error message will provide specific guidance"
  puts "  - Try the 'Try in New Window' button"
  puts "  - Use incognito mode to isolate browser state issues"
  puts "  - Check the Technical Details section for debugging info"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n💡 Key Changes Made:"
puts "1. Removed invalid getSessionFromUrl() method"
puts "2. Using correct exchangeCodeForSession() for PKCE"
puts "3. Enhanced session detection and retry logic"
puts "4. Better error messages with specific troubleshooting steps"
puts "5. Clear data functionality that removes cookies and storage"

puts "\n" + "=" * 80
puts "Corrected PKCE fix complete"
puts "=" * 80