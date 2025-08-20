# DNS Conflict Solutions for OverSkill WFP

## Problem
`*.overskill.com` wildcard Worker route will override existing CNAMEs like `dev.overskill.com` → internal Grok.

## Solution Options

### Option 1: Smart Dispatch Worker (RECOMMENDED)
**Pros**: Simple, immediate, flexible
**Cons**: All requests still hit the Worker first

Update dispatch worker to check reserved subdomains:
```javascript
function isReservedSubdomain(hostname) {
  const reserved = [
    'dev.overskill.com',     // Internal Grok
    'www.overskill.com',     // Main website  
    'api.overskill.com',     // API endpoints
    'admin.overskill.com',   // Admin panel
  ];
  return reserved.includes(hostname.toLowerCase());
}
```

If reserved, return 404/503 to let Cloudflare fall back to original DNS.

### Option 2: Specific Route Patterns 
**Pros**: DNS-level isolation
**Cons**: Requires route management as apps scale

Instead of `*.overskill.com/*`, create specific routes:
- `app-*.overskill.com/*` (for apps with "app-" prefix)
- `[a-z0-9]{6}.overskill.com/*` (for 6-char obfuscated IDs)

### Option 3: Subdomain Strategy Change
**Pros**: Complete separation
**Cons**: Less clean URLs

Use prefix for all WFP apps:
- `app-{id}.overskill.com` instead of `{id}.overskill.com`
- `wfp-{id}.overskill.com` 

## Current Implementation Plan

Using **Option 1** with these reserved subdomains:
- `dev.overskill.com` → Protected (your Grok)
- `www.overskill.com` → Protected (main site)
- `api.overskill.com` → Protected (API)
- `admin.overskill.com` → Protected (admin)

Worker returns 404 for reserved subdomains, allowing original DNS to work.

## Testing Strategy

1. Deploy updated dispatch worker with protection
2. Test `dev.overskill.com` still works for Grok
3. Test WFP apps still work (e.g., `nxkkre.overskill.com`)
4. Add more reserved subdomains as needed

## Migration Path

If conflicts arise later:
1. Identify conflicting subdomain
2. Add to reserved list
3. Redeploy dispatch worker
4. Original DNS takes over immediately