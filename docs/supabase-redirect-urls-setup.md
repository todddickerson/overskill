# Supabase Redirect URLs Configuration for OverSkill

## Quick Fix - Add These URLs to Supabase Dashboard

Go to **Supabase Dashboard → Authentication → URL Configuration** and add:

### Site URL
```
https://overskill.app
```

### Redirect URLs (Add ALL of these)
```
https://preview-**.overskill.app/**
https://app-**.overskill.app/**
http://localhost:3000/**
http://localhost:5173/**
```

## Why This Works

Supabase supports wildcard patterns:
- `**` matches any characters (including slashes)
- This covers all our dynamic app URLs:
  - `https://preview-1.overskill.app/auth/callback`
  - `https://preview-61.overskill.app/login`
  - `https://preview-999.overskill.app/any/path`

## Step-by-Step Setup

1. **Login to Supabase Dashboard**
   - Go to your project
   - Navigate to Authentication → URL Configuration

2. **Set Site URL**
   ```
   https://overskill.app
   ```

3. **Add Redirect URLs**
   Click "Add URL" and add each of these:
   ```
   https://preview-**.overskill.app/**
   https://app-**.overskill.app/**
   http://localhost:3000/**
   http://localhost:5173/**
   ```

4. **Save Changes**

## Update Auth Templates (Already Done)

Our templates already use dynamic origin:
```typescript
const { error } = await supabase.auth.signInWithOAuth({
  provider,
  options: {
    redirectTo: `${window.location.origin}/auth/callback`
  }
})
```

This automatically uses:
- `https://preview-61.overskill.app/auth/callback` in production
- `http://localhost:3000/auth/callback` in development

## Testing

After adding the redirect URLs:

1. **Test OAuth Login**
   - Go to https://preview-61.overskill.app/login
   - Click "Continue with GitHub"
   - Should redirect to GitHub
   - Should return to `https://preview-61.overskill.app/auth/callback`
   - Should redirect to dashboard

2. **Test Password Reset**
   - Go to /forgot-password
   - Enter email
   - Check email for reset link
   - Should redirect to correct app URL

## Environment Variables

Each app automatically gets:
```javascript
window.ENV = {
  APP_ID: "61",
  SUPABASE_URL: "https://bsbgwixlklvgeoxvjmtb.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGc..."
}
```

## Notes

- Free Supabase tier supports wildcards ✅
- No need for per-app configuration
- Works for unlimited apps
- Covers all environments (dev, preview, production)

## Alternative for Production

For production apps with custom domains:
```
https://*.customdomain.com/**
https://customdomain.com/**
```

## Security Considerations

- Only add trusted domains
- Wildcards are safe when scoped to your domain
- Don't use overly broad patterns like `https://**`