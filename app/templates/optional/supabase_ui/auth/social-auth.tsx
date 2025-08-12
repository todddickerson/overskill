import { useState } from 'react'
import { supabase } from '@/lib/supabase'
import { Provider } from '@supabase/supabase-js'

const providers = [
  { name: 'github', label: 'GitHub', icon: '🐙' },
  { name: 'google', label: 'Google', icon: '🔍' },
  { name: 'discord', label: 'Discord', icon: '💬' },
  { name: 'twitter', label: 'Twitter', icon: '🐦' },
] as const

export function SocialAuth() {
  const [loading, setLoading] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const handleSocialLogin = async (provider: Provider) => {
    try {
      setLoading(provider)
      setError(null)
      
      const { error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: `${window.location.origin}/auth/callback`,
        }
      })
      
      if (error) throw error
    } catch (error: any) {
      setError(error.message || 'An error occurred during authentication')
      setLoading(null)
    }
  }

  return (
    <div className="w-full space-y-4">
      <div className="relative">
        <div className="absolute inset-0 flex items-center">
          <div className="w-full border-t border-gray-300" />
        </div>
        <div className="relative flex justify-center text-sm">
          <span className="px-4 bg-white text-gray-500">Or continue with</span>
        </div>
      </div>

      {error && (
        <div className="p-3 rounded-md text-sm bg-red-50 text-red-800 border border-red-200">
          {error}
        </div>
      )}

      <div className="grid grid-cols-2 gap-3">
        {providers.map((provider) => (
          <button
            key={provider.name}
            onClick={() => handleSocialLogin(provider.name as Provider)}
            disabled={loading !== null}
            className="flex items-center justify-center px-4 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <span className="mr-2">{provider.icon}</span>
            {loading === provider.name ? (
              <span>Connecting...</span>
            ) : (
              <span>{provider.label}</span>
            )}
          </button>
        ))}
      </div>
    </div>
  )
}