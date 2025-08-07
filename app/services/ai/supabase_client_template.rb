# Supabase client template that gracefully handles missing environment variables
module Ai
  class SupabaseClientTemplate
    class << self
      def generate
        <<~TYPESCRIPT
          import { createClient } from '@supabase/supabase-js'

          // Helper to safely get environment variables from multiple sources
          function getEnvVar(key: string, fallback?: string): string {
            // Try Vite environment variables
            if ((import.meta as any)?.env?.[key]) {
              return (import.meta as any).env[key]
            }
            
            // Try window-injected environment variables from Cloudflare
            if ((window as any)?.ENV?.[key]) {
              return (window as any).ENV[key]
            }
            
            // Try direct window properties (legacy)
            if ((window as any)?.[key]) {
              return (window as any)[key]
            }
            
            if (fallback) {
              return fallback
            }
            
            throw new Error(`Environment variable ${key} is not defined. Please check your .env file or deployment configuration.`)
          }

          // Get Supabase configuration - fail fast with clear error
          let supabaseUrl: string
          let supabaseAnonKey: string

          try {
            // Try to get from environment with VITE_ prefix first
            supabaseUrl = getEnvVar('VITE_SUPABASE_URL')
            supabaseAnonKey = getEnvVar('VITE_SUPABASE_ANON_KEY')
          } catch {
            try {
              // Try without VITE_ prefix (from window.ENV)
              supabaseUrl = getEnvVar('SUPABASE_URL')
              supabaseAnonKey = getEnvVar('SUPABASE_ANON_KEY')
            } catch (error) {
              // Show clear error to user
              const errorMessage = `
                🚨 SUPABASE CONFIGURATION ERROR 🚨
                
                The app cannot connect to the database.
                
                Missing environment variables:
                - SUPABASE_URL
                - SUPABASE_ANON_KEY
                
                ACTION REQUIRED:
                1. Check your .env file for these variables
                2. Contact support if this is a deployed app
                3. Ensure the deployment includes these environment variables
                
                Technical details: ${error}
              `
              
              console.error(errorMessage)
              
              // Show alert to user (they need to take action)
              if (typeof window !== 'undefined') {
                // Create error overlay
                const errorDiv = document.createElement('div')
                errorDiv.style.cssText = `
                  position: fixed;
                  top: 0;
                  left: 0;
                  right: 0;
                  bottom: 0;
                  background: rgba(220, 38, 38, 0.95);
                  color: white;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  z-index: 999999;
                  font-family: system-ui, -apple-system, sans-serif;
                `
                errorDiv.innerHTML = `
                  <div style="max-width: 600px; padding: 2rem; text-align: center;">
                    <h1 style="font-size: 2rem; margin-bottom: 1rem;">⚠️ Configuration Error</h1>
                    <p style="font-size: 1.2rem; margin-bottom: 1rem;">
                      This app requires database configuration that is currently missing.
                    </p>
                    <div style="background: rgba(0,0,0,0.2); padding: 1rem; border-radius: 8px; margin: 1rem 0;">
                      <p style="margin: 0.5rem 0;"><strong>Missing:</strong></p>
                      <code style="display: block; margin: 0.5rem 0;">SUPABASE_URL</code>
                      <code style="display: block; margin: 0.5rem 0;">SUPABASE_ANON_KEY</code>
                    </div>
                    <p style="font-size: 0.9rem; opacity: 0.9;">
                      Please contact the app administrator or check deployment settings.
                    </p>
                  </div>
                `
                document.body.appendChild(errorDiv)
              }
              
              // Throw error to prevent app from continuing with broken state
              throw new Error('Supabase configuration is required but not found')
            }
          }

          // Create Supabase client
          export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
            auth: {
              persistSession: true,
              autoRefreshToken: true,
              detectSessionInUrl: true,
              flowType: 'pkce'
            }
          })

          // Helper to check if Supabase is properly configured
          export const isSupabaseConfigured = (): boolean => {
            return !supabaseUrl.includes('placeholder') && !supabaseAnonKey.includes('placeholder')
          }

          // RLS context setter for multi-tenant apps
          export const setRLSContext = async (userId: string): Promise<void> => {
            if (!isSupabaseConfigured()) {
              console.warn('Supabase not configured, skipping RLS context')
              return
            }
            
            try {
              await supabase.rpc('set_config', {
                setting_name: 'app.current_user_id',
                new_value: userId,
                is_local: true
              })
            } catch (error) {
              console.error('Failed to set RLS context:', error)
            }
          }

          // Export configuration status for UI components to check
          export const supabaseConfig = {
            url: supabaseUrl,
            isConfigured: isSupabaseConfigured(),
            hasPlaceholder: supabaseUrl.includes('placeholder')
          }

          // Log configuration status (only in development)
          if (import.meta.env?.DEV || (window as any)?.ENV?.ENVIRONMENT === 'development') {
            console.log('Supabase Client Status:', {
              configured: isSupabaseConfigured(),
              url: supabaseUrl.replace(/https?:\\/\\/([^.]+)\\..*/, 'https://$1.supabase.co'), // Mask for security
              hasEnvVars: {
                VITE_SUPABASE_URL: !!(import.meta as any)?.env?.VITE_SUPABASE_URL,
                SUPABASE_URL: !!(window as any)?.ENV?.SUPABASE_URL
              }
            })
          }
        TYPESCRIPT
      end
    end
  end
end