# OverSkill.com Custom Domain Setup for WFP
**Date**: January 20, 2025  
**Purpose**: Enable subdomain-style URLs for Workers for Platforms

## Overview

Setting up `*.overskill.com` will enable each app to have a unique-looking subdomain:
- `abc123.overskill.com` (Production)
- `preview-abc123.overskill.com` (Preview)  
- `staging-abc123.overskill.com` (Staging)

All subdomains route through the single dispatch worker but appear as individual URLs.

## DNS Configuration Steps

### 1. Add Cloudflare Zone (if not already done)
1. Go to Cloudflare Dashboard
2. Add `overskill.com` as a zone
3. Update nameservers at domain registrar

### 2. Create Wildcard CNAME Record
Add DNS record in Cloudflare:
```
Type: CNAME
Name: *
Target: overskill-dispatch.toddspontentcomsaccount.workers.dev
Proxy: 🟠 Proxied (Orange Cloud)
TTL: Auto
```

### 3. Add Custom Domain Route in Workers
In Cloudflare Dashboard > Workers & Pages > overskill-dispatch:
1. Go to Settings > Triggers
2. Add Custom Domain: `*.overskill.com`
3. This connects all subdomains to the dispatch worker

### 4. Configure SSL Certificate
Cloudflare automatically generates wildcard SSL certificates for `*.overskill.com`

## Testing the Setup

### 1. Verify DNS Resolution
```bash
# Test that subdomains resolve to Cloudflare
nslookup test123.overskill.com
# Should show Cloudflare IP addresses
```

### 2. Test Dispatch Worker Routing
```bash
# Test landing page
curl https://test123.overskill.com

# Should return dispatch worker landing page with routing info
```

### 3. Test Customer Script Routing
```bash
# Test actual app (after deploying a test script)
curl https://jlxxrj.overskill.com
# Should route to customer script in WFP namespace
```

## URL Migration Strategy

### Current State (Path-based)
```
https://overskill-dispatch.toddspontentcomsaccount.workers.dev/app/jlxxrj
```

### Target State (Subdomain-style) 
```
https://jlxxrj.overskill.com
```

### Migration Approach
1. **Phase 1**: Set up DNS and test routing
2. **Phase 2**: Update WorkersForPlatformsService to generate overskill.com URLs
3. **Phase 3**: Update App Builder UI to show new URLs
4. **Phase 4**: Keep workers.dev as fallback for development

## Code Changes Required

### Update Default URL Generation
In `WorkersForPlatformsService`:
```ruby
def generate_app_url(script_name, environment)
  # Switch to subdomain-style as primary
  "https://#{script_name}.overskill.com"
end
```

### Update App Model URLs
Add migration to update existing app URLs:
```ruby
# Update all apps to use overskill.com URLs
App.find_each do |app|
  next unless app.obfuscated_id.present?
  
  script_name = app.obfuscated_id.downcase
  app.update!(
    production_url: "https://#{script_name}.overskill.com",
    preview_url: "https://preview-#{script_name}.overskill.com",
    staging_url: "https://staging-#{script_name}.overskill.com"
  )
end
```

## Benefits After Setup

### Professional URLs
✅ `abc123.overskill.com` vs ❌ `dispatch-worker.account.workers.dev/app/abc123`

### SEO Advantages
- Each app appears to have its own domain
- Better search engine indexing
- Professional appearance for users

### Branding Consistency
- All URLs under overskill.com domain
- Consistent with main platform branding
- Easier to market and explain

## Monitoring

### DNS Propagation
- Check DNS propagation globally: https://dnschecker.org
- Test from different locations

### SSL Certificate Status
- Verify wildcard certificate in Cloudflare SSL/TLS tab
- Test HTTPS on various subdomains

### Worker Performance
- Monitor dispatch worker metrics in Cloudflare Analytics
- Check routing success rates

## Rollback Plan

If issues arise, revert URL generation back to path-based:
```ruby
def generate_app_url(script_name, environment)
  # Rollback to path-based routing
  dispatch_url = "https://overskill-dispatch.#{get_account_subdomain}.workers.dev"
  "#{dispatch_url}/app/#{script_name}"
end
```

DNS changes are non-destructive and can be removed easily.

## Estimated Timeline

- **DNS Setup**: 5 minutes
- **DNS Propagation**: 2-24 hours globally  
- **Testing**: 1 hour
- **Code Updates**: 2 hours
- **Migration**: 1 hour

**Total**: ~1 day for complete setup and migration

## Success Criteria

✅ `test123.overskill.com` resolves to dispatch worker  
✅ Dispatch worker correctly routes subdomain requests  
✅ Customer apps accessible via subdomain URLs  
✅ SSL certificates working for all subdomains  
✅ Existing apps updated with new URLs  

**Ready to implement once DNS configuration is approved!**