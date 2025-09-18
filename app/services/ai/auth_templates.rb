# Standardized authentication templates for AI-generated apps
module Ai
  class AuthTemplates
    class << self
      def login_page
        <<~TSX
          import { useState } from 'react'
          import { Link, useNavigate, useLocation } from 'react-router-dom'
          import { supabase } from '../../lib/supabase'
          import { SocialButtons } from '../../components/auth/SocialButtons'

          export function Login() {
            const [email, setEmail] = useState('')
            const [password, setPassword] = useState('')
            const [loading, setLoading] = useState(false)
            const [error, setError] = useState<string | null>(null)
            const navigate = useNavigate()
            const location = useLocation()
            
            const from = location.state?.from?.pathname || '/dashboard'

            const handleSubmit = async (e: React.FormEvent) => {
              e.preventDefault()
              setLoading(true)
              setError(null)
              
              const { data, error } = await supabase.auth.signInWithPassword({
                email,
                password
              })
              
              if (error) {
                setError(error.message)
                setLoading(false)
              } else if (data.user) {
                navigate(from, { replace: true })
              }
            }

            return (
              <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
                <div className="max-w-md w-full space-y-8">
                  <div>
                    <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
                      Sign in to your account
                    </h2>
                    <p className="mt-2 text-center text-sm text-gray-600">
                      Or{' '}
                      <Link to="/signup" className="font-medium text-indigo-600 hover:text-indigo-500">
                        create a new account
                      </Link>
                    </p>
                  </div>
                  
                  <div className="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
                    <SocialButtons />
                    
                    <div className="mt-6">
                      <div className="relative">
                        <div className="absolute inset-0 flex items-center">
                          <div className="w-full border-t border-gray-300" />
                        </div>
                        <div className="relative flex justify-center text-sm">
                          <span className="px-2 bg-white text-gray-500">Or continue with</span>
                        </div>
                      </div>
                    </div>

                    <form className="mt-6 space-y-6" onSubmit={handleSubmit}>
                      {error && (
                        <div className="rounded-md bg-red-50 p-4">
                          <p className="text-sm text-red-800">{error}</p>
                        </div>
                      )}
                      
                      <div>
                        <label htmlFor="email" className="block text-sm font-medium text-gray-700">
                          Email address
                        </label>
                        <input
                          id="email"
                          name="email"
                          type="email"
                          autoComplete="email"
                          required
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      </div>

                      <div>
                        <label htmlFor="password" className="block text-sm font-medium text-gray-700">
                          Password
                        </label>
                        <input
                          id="password"
                          name="password"
                          type="password"
                          autoComplete="current-password"
                          required
                          value={password}
                          onChange={(e) => setPassword(e.target.value)}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      </div>

                      <div className="flex items-center justify-between">
                        <div className="text-sm">
                          <Link to="/forgot-password" className="font-medium text-indigo-600 hover:text-indigo-500">
                            Forgot your password?
                          </Link>
                        </div>
                      </div>

                      <button
                        type="submit"
                        disabled={loading}
                        className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {loading ? 'Signing in...' : 'Sign in'}
                      </button>
                    </form>
                  </div>
                </div>
              </div>
            )
          }
        TSX
      end

      def signup_page
        <<~TSX
          import { useState } from 'react'
          import { Link } from 'react-router-dom'
          import { supabase } from '../../lib/supabase'
          import { SocialButtons } from '../../components/auth/SocialButtons'

          export function SignUp() {
            const [email, setEmail] = useState('')
            const [password, setPassword] = useState('')
            const [confirmPassword, setConfirmPassword] = useState('')
            const [loading, setLoading] = useState(false)
            const [error, setError] = useState<string | null>(null)
            const [success, setSuccess] = useState(false)

            const handleSubmit = async (e: React.FormEvent) => {
              e.preventDefault()
              
              if (password !== confirmPassword) {
                setError('Passwords do not match')
                return
              }
              
              setLoading(true)
              setError(null)
              
              const { data, error } = await supabase.auth.signUp({
                email,
                password,
                options: {
                  emailRedirectTo: `${window.location.origin}/auth/callback`
                }
              })
              
              if (error) {
                setError(error.message)
                setLoading(false)
              } else if (data.user) {
                setSuccess(true)
              }
            }

            if (success) {
              return (
                <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4">
                  <div className="max-w-md w-full space-y-8 text-center">
                    <div className="bg-green-50 p-6 rounded-lg">
                      <h2 className="text-2xl font-bold text-green-900 mb-4">Check your email!</h2>
                      <p className="text-green-700">
                        We've sent you a confirmation link. Please check your email and click the link to activate your account.
                      </p>
                    </div>
                  </div>
                </div>
              )
            }

            return (
              <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
                <div className="max-w-md w-full space-y-8">
                  <div>
                    <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
                      Create your account
                    </h2>
                    <p className="mt-2 text-center text-sm text-gray-600">
                      Or{' '}
                      <Link to="/login" className="font-medium text-indigo-600 hover:text-indigo-500">
                        sign in to existing account
                      </Link>
                    </p>
                  </div>
                  
                  <div className="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
                    <SocialButtons />
                    
                    <div className="mt-6">
                      <div className="relative">
                        <div className="absolute inset-0 flex items-center">
                          <div className="w-full border-t border-gray-300" />
                        </div>
                        <div className="relative flex justify-center text-sm">
                          <span className="px-2 bg-white text-gray-500">Or sign up with</span>
                        </div>
                      </div>
                    </div>

                    <form className="mt-6 space-y-6" onSubmit={handleSubmit}>
                      {error && (
                        <div className="rounded-md bg-red-50 p-4">
                          <p className="text-sm text-red-800">{error}</p>
                        </div>
                      )}
                      
                      <div>
                        <label htmlFor="email" className="block text-sm font-medium text-gray-700">
                          Email address
                        </label>
                        <input
                          id="email"
                          name="email"
                          type="email"
                          autoComplete="email"
                          required
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      </div>

                      <div>
                        <label htmlFor="password" className="block text-sm font-medium text-gray-700">
                          Password
                        </label>
                        <input
                          id="password"
                          name="password"
                          type="password"
                          autoComplete="new-password"
                          required
                          value={password}
                          onChange={(e) => setPassword(e.target.value)}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      </div>

                      <div>
                        <label htmlFor="confirm-password" className="block text-sm font-medium text-gray-700">
                          Confirm Password
                        </label>
                        <input
                          id="confirm-password"
                          name="confirm-password"
                          type="password"
                          autoComplete="new-password"
                          required
                          value={confirmPassword}
                          onChange={(e) => setConfirmPassword(e.target.value)}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                        />
                      </div>

                      <button
                        type="submit"
                        disabled={loading}
                        className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {loading ? 'Creating account...' : 'Sign up'}
                      </button>
                    </form>
                  </div>
                </div>
              </div>
            )
          }
        TSX
      end

      def social_buttons_component
        <<~TSX
          import { useState } from 'react'
          import { supabase } from '../../lib/supabase'

          type Provider = 'google' | 'github'

          export function SocialButtons() {
            const [loading, setLoading] = useState<Provider | null>(null)

            const handleSocialLogin = async (provider: Provider) => {
              setLoading(provider)
              
              const { error } = await supabase.auth.signInWithOAuth({
                provider,
                options: {
                  redirectTo: `${window.location.origin}/auth/callback`
                }
              })
              
              if (error) {
                console.error('Social login error:', error)
                setLoading(null)
              }
            }

            return (
              <div className="space-y-3">
                <button
                  onClick={() => handleSocialLogin('google')}
                  disabled={loading !== null}
                  className="w-full flex items-center justify-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {loading === 'google' ? (
                    <span>Connecting...</span>
                  ) : (
                    <>
                      <svg className="w-5 h-5 mr-2" viewBox="0 0 24 24">
                        <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                        <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                        <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                        <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                      </svg>
                      Continue with Google
                    </>
                  )}
                </button>

                <button
                  onClick={() => handleSocialLogin('github')}
                  disabled={loading !== null}
                  className="w-full flex items-center justify-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {loading === 'github' ? (
                    <span>Connecting...</span>
                  ) : (
                    <>
                      <svg className="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
                        <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
                      </svg>
                      Continue with GitHub
                    </>
                  )}
                </button>
              </div>
            )
          }
        TSX
      end

      def forgot_password_page
        <<~TSX
          import { useState } from 'react'
          import { Link } from 'react-router-dom'
          import { supabase } from '../../lib/supabase'

          export function ForgotPassword() {
            const [email, setEmail] = useState('')
            const [loading, setLoading] = useState(false)
            const [success, setSuccess] = useState(false)
            const [error, setError] = useState<string | null>(null)

            const handleSubmit = async (e: React.FormEvent) => {
              e.preventDefault()
              setLoading(true)
              setError(null)
              
              const { error } = await supabase.auth.resetPasswordForEmail(email, {
                redirectTo: `${window.location.origin}/update-password`,
              })
              
              if (error) {
                setError(error.message)
                setLoading(false)
              } else {
                setSuccess(true)
              }
            }

            if (success) {
              return (
                <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4">
                  <div className="max-w-md w-full space-y-8 text-center">
                    <div className="bg-green-50 p-6 rounded-lg">
                      <h2 className="text-2xl font-bold text-green-900 mb-4">Check your email!</h2>
                      <p className="text-green-700">
                        We've sent you a password reset link. Please check your email and follow the instructions.
                      </p>
                      <Link to="/login" className="mt-4 inline-block text-indigo-600 hover:text-indigo-500">
                        Back to login
                      </Link>
                    </div>
                  </div>
                </div>
              )
            }

            return (
              <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4">
                <div className="max-w-md w-full space-y-8">
                  <div>
                    <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
                      Reset your password
                    </h2>
                    <p className="mt-2 text-center text-sm text-gray-600">
                      Enter your email address and we'll send you a link to reset your password.
                    </p>
                  </div>
                  
                  <div className="bg-white py-8 px-4 shadow sm:rounded-lg sm:px-10">
                    <form className="space-y-6" onSubmit={handleSubmit}>
                      {error && (
                        <div className="rounded-md bg-red-50 p-4">
                          <p className="text-sm text-red-800">{error}</p>
                        </div>
                      )}
                      
                      <div>
                        <label htmlFor="email" className="block text-sm font-medium text-gray-700">
                          Email address
                        </label>
                        <input
                          id="email"
                          name="email"
                          type="email"
                          autoComplete="email"
                          required
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          className="mt-1 block w-full px-3 py-2 border border-gray-300 rounded-md shadow-sm text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-indigo-500 focus:border-indigo-500 sm:text-sm"
                          placeholder="Enter your email"
                        />
                      </div>

                      <button
                        type="submit"
                        disabled={loading}
                        className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {loading ? 'Sending...' : 'Send reset link'}
                      </button>
                      
                      <div className="text-center">
                        <Link to="/login" className="text-sm text-indigo-600 hover:text-indigo-500">
                          Back to login
                        </Link>
                      </div>
                    </form>
                  </div>
                </div>
              </div>
            )
          }
        TSX
      end

      def auth_callback_page
        <<~TSX
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
                      userFriendlyError = 'OAuth validation failed. This may be due to browser storage issues. Please try:\\n\\n1. Clear your browser data for this site\\n2. Try using an incognito/private window\\n3. Disable browser extensions temporarily'
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
      end

      def protected_route_component
        <<~TSX
          import { Navigate, useLocation } from 'react-router-dom'
          import { useAuth } from '../../hooks/useAuth'

          interface ProtectedRouteProps {
            children: React.ReactNode
          }

          export function ProtectedRoute({ children }: ProtectedRouteProps) {
            const { user, loading } = useAuth()
            const location = useLocation()

            if (loading) {
              return (
                <div className="min-h-screen flex items-center justify-center">
                  <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600"></div>
                </div>
              )
            }

            if (!user) {
              return <Navigate to="/login" state={{ from: location }} replace />
            }

            return <>{children}</>
          }
        TSX
      end

      def use_auth_hook
        <<~TSX
          import { useEffect, useState } from 'react'
          import { User } from '@supabase/supabase-js'
          import { supabase } from '../lib/supabase'

          export function useAuth() {
            const [user, setUser] = useState<User | null>(null)
            const [loading, setLoading] = useState(true)

            useEffect(() => {
              // Get initial session
              supabase.auth.getSession().then(({ data: { session } }) => {
                setUser(session?.user ?? null)
                setLoading(false)
              })

              // Listen for auth changes
              const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
                setUser(session?.user ?? null)
              })

              return () => subscription.unsubscribe()
            }, [])

            const signOut = async () => {
              await supabase.auth.signOut()
            }

            return { user, loading, signOut }
          }
        TSX
      end

      def router_app_template
        <<~TSX
          import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
          import { ProtectedRoute } from './components/auth/ProtectedRoute'

          // Auth pages
          import { Login } from './pages/auth/Login'
          import { SignUp } from './pages/auth/SignUp'
          import { ForgotPassword } from './pages/auth/ForgotPassword'
          import { AuthCallback } from './pages/auth/AuthCallback'

          // App pages
          import { Dashboard } from './pages/Dashboard'

          export function App() {
            return (
              <BrowserRouter>
                <Routes>
                  {/* Public routes */}
                  <Route path="/login" element={<Login />} />
                  <Route path="/signup" element={<SignUp />} />
                  <Route path="/forgot-password" element={<ForgotPassword />} />
                  <Route path="/auth/callback" element={<AuthCallback />} />
                  
                  {/* Protected routes */}
                  <Route path="/dashboard" element={
                    <ProtectedRoute>
                      <Dashboard />
                    </ProtectedRoute>
                  } />
                  
                  {/* Default redirect */}
                  <Route path="/" element={<Navigate to="/dashboard" replace />} />
                </Routes>
              </BrowserRouter>
            )
          }
        TSX
      end

      def package_json_template
        <<~JSON
          {
            "name": "overskill-app",
            "private": true,
            "version": "0.0.0",
            "type": "module",
            "scripts": {
              "dev": "vite",
              "build": "tsc && vite build",
              "preview": "vite preview"
            },
            "dependencies": {
              "react": "^18.2.0",
              "react-dom": "^18.2.0",
              "react-router-dom": "^6.20.0",
              "@supabase/supabase-js": "^2.39.0"
            },
            "devDependencies": {
              "@types/react": "^18.2.0",
              "@types/react-dom": "^18.2.0",
              "@vitejs/plugin-react-swc": "^3.11.0",
              "autoprefixer": "^10.4.16",
              "postcss": "^8.4.32",
              "tailwindcss": "^3.3.6",
              "typescript": "^5.0.0",
              "vite": "^5.0.0"
            }
          }
        JSON
      end

      # Generate all auth files for an app
      def generate_auth_files(app)
        # Always include the supabase client with auth files
        require_relative "supabase_client_template"

        files = [
          {path: "src/lib/supabase.ts", content: Ai::SupabaseClientTemplate.generate},
          {path: "src/pages/auth/Login.tsx", content: login_page},
          {path: "src/pages/auth/SignUp.tsx", content: signup_page},
          {path: "src/pages/auth/ForgotPassword.tsx", content: forgot_password_page},
          {path: "src/pages/auth/AuthCallback.tsx", content: auth_callback_page},
          {path: "src/components/auth/SocialButtons.tsx", content: social_buttons_component},
          {path: "src/components/auth/ProtectedRoute.tsx", content: protected_route_component},
          {path: "src/hooks/useAuth.ts", content: use_auth_hook}
        ]

        files.each do |file|
          app.app_files.create!(
            path: file[:path],
            content: file[:content],
            team: app.team
          )
        end
      end
    end
  end
end
