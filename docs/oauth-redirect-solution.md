# OAuth Redirect URL Solution for Multi-App System

## Problem
OAuth redirected to localhost:3000 instead of the app's preview URL (e.g., https://preview-61.overskill.app)

## Root Cause
Supabase requires redirect URLs to be whitelisted in the dashboard, but we have dynamic app URLs:
- `https://preview-1.overskill.app`
- `https://preview-2.overskill.app`
- `https://preview-N.overskill.app`

## Solutions

### Option 1: Wildcard Redirect URL (Recommended)
Configure Supabase to accept wildcard patterns:
```
https://preview-*.overskill.app/auth/callback
https://*.overskill.app/auth/callback
```

**Implementation:**
1. In Supabase Dashboard → Authentication → URL Configuration
2. Add site URL: `https://overskill.app`
3. Add redirect URLs:
   - `https://preview-*.overskill.app/auth/callback`
   - `https://app-*.overskill.app/auth/callback`
   - `http://localhost:3000/auth/callback` (for dev)

### Option 2: Central Auth Proxy
Use a single auth endpoint that redirects to the correct app:
```
https://auth.overskill.app/callback?app_id=61&return_to=preview-61.overskill.app
```

**Implementation:**
1. Create auth subdomain
2. Handle OAuth callback centrally
3. Redirect to correct app with token

### Option 3: Dynamic Redirect URL via State Parameter
Pass the app URL in OAuth state parameter:

```typescript
const { error } = await supabase.auth.signInWithOAuth({
  provider,
  options: {
    redirectTo: `https://auth.overskill.app/callback`,
    scopes: 'email',
    queryParams: {
      state: btoa(JSON.stringify({
        app_id: window.ENV.APP_ID,
        return_url: window.location.origin
      }))
    }
  }
})
```

### Option 4: Per-App Supabase Projects (Not Scalable)
Each app gets its own Supabase project with configured URLs.
- ❌ Too expensive
- ❌ Hard to manage
- ❌ Not scalable

## Recommended Implementation

### Step 1: Update Supabase Dashboard
Add these redirect URLs:
```
https://preview-*.overskill.app/auth/callback
https://app-*.overskill.app/auth/callback
http://localhost:3000/auth/callback
http://localhost:5173/auth/callback
```

### Step 2: Update Auth Templates
Ensure redirectTo uses current origin:

```typescript
// In SocialButtons.tsx
const handleSocialLogin = async (provider: Provider) => {
  setLoading(provider)
  
  // Get the correct redirect URL based on environment
  const redirectUrl = `${window.location.origin}/auth/callback`
  
  const { error } = await supabase.auth.signInWithOAuth({
    provider,
    options: {
      redirectTo: redirectUrl,
      // Optional: Include app context
      queryParams: {
        app_id: window.ENV?.APP_ID
      }
    }
  })
  
  if (error) {
    console.error('Social login error:', error)
    setLoading(null)
  }
}
```

### Step 3: Update AuthCallback Component
Handle the OAuth callback properly:

```typescript
// In AuthCallback.tsx
export function AuthCallback() {
  const navigate = useNavigate()

  useEffect(() => {
    // Handle the OAuth callback
    const handleCallback = async () => {
      const { data: { session }, error } = await supabase.auth.getSession()
      
      if (error) {
        console.error('Auth callback error:', error)
        navigate('/login?error=auth_failed')
        return
      }
      
      if (session) {
        // Successful authentication
        navigate('/dashboard')
      } else {
        navigate('/login')
      }
    }
    
    handleCallback()
  }, [navigate])

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <div className="text-center">
        <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-indigo-600 mx-auto"></div>
        <p className="mt-4 text-gray-600">Completing sign in...</p>
      </div>
    </div>
  )
}
```

## Environment Variables
Each app needs these in their build/runtime:
```bash
VITE_SUPABASE_URL=https://bsbgwixlklvgeoxvjmtb.supabase.co
VITE_SUPABASE_ANON_KEY=eyJhbGc...
VITE_APP_URL=https://preview-61.overskill.app  # NEW: App's public URL
```

## Testing Checklist
- [ ] Login with email/password works
- [ ] OAuth redirect goes to correct app URL
- [ ] OAuth callback successfully authenticates
- [ ] User is redirected to dashboard after auth
- [ ] Logout works correctly
- [ ] Password reset email contains correct URL

## Notes
- Supabase allows wildcard domains in Pro/Team plans
- Free tier requires exact URL matching
- Consider upgrading Supabase plan for production
- Alternative: Use Supabase's custom domain feature