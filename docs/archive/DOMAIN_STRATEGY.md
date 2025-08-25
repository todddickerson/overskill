# Domain Strategy: workers.dev vs Custom Domain

## Current Decision: Start with workers.dev, migrate to custom domain later

## workers.dev Domain (Initial Phase)

### ✅ Pros
- **Zero Configuration**: Works immediately, no DNS setup required
- **Free SSL**: Automatic HTTPS with Cloudflare certificates
- **Fast Deployment**: Can start testing immediately
- **No DNS Propagation**: Changes are instant
- **Built-in DDoS Protection**: Cloudflare's network protection included
- **Perfect for Development**: Great for preview/staging environments
- **Subdomain Flexibility**: Easy pattern like `app-123.overskill.workers.dev`

### ❌ Cons
- **Branding**: Shows "workers.dev" instead of your brand
- **SEO Limitations**: Harder to rank on shared domain
- **Trust**: Some users may not trust workers.dev domains
- **No Domain Control**: Can't set custom DNS records
- **Rate Limits**: Shared domain rate limits (though very high)

### Example URLs
```
Preview: preview-ultrathink-abc123.overskill.workers.dev
Staging: staging-ultrathink-abc123.overskill.workers.dev
Production: ultrathink-abc123.overskill.workers.dev
```

## Custom Domain (Production Phase)

### ✅ Pros
- **Professional Branding**: `ultrathink.apps.overskill.com`
- **SEO Benefits**: Better search engine rankings
- **User Trust**: Professional appearance increases conversions
- **Full DNS Control**: Can add MX, TXT, other records
- **Custom Subdomains**: Unlimited subdomain patterns
- **Analytics**: Better tracking with your own domain
- **Email Integration**: Can use domain for email

### ❌ Cons
- **DNS Setup Required**: Initial configuration needed
- **SSL Certificate**: Need to manage certificates (though Cloudflare helps)
- **DNS Propagation**: Changes take 24-48 hours
- **Cost**: Domain registration/renewal fees
- **Complexity**: More moving parts to manage

### Example URLs
```
Preview: preview.ultrathink.overskill.app
Staging: staging.ultrathink.overskill.app
Production: ultrathink.overskill.app
```

## Migration Strategy

### Phase 1: Development (Now - 1 month)
- Use `*.overskill.workers.dev`
- Test all functionality
- Validate WFP architecture
- No DNS complexity

### Phase 2: Beta (Month 2)
- Set up custom domain
- Keep workers.dev as fallback
- A/B test both domains
- Monitor performance

### Phase 3: Production (Month 3+)
- Full migration to custom domain
- Redirect workers.dev to custom
- Professional URLs for all apps
- Complete branding control

## Recommended Approach

**Start with workers.dev NOW because:**
1. Zero setup time - can deploy today
2. Perfect for testing WFP architecture
3. No DNS configuration blocking progress
4. Easy to migrate later (just update dispatch Worker)

**Plan custom domain for Month 2 when:**
1. Architecture is proven
2. First customers are onboarding
3. Branding becomes important
4. You have time for DNS setup

## Technical Implementation

### Workers.dev Routing (Current)
```javascript
// Dispatch worker handles subdomain routing
const subdomain = url.hostname.split('.')[0];
// preview-ultrathink-abc123 → routes to preview namespace
```

### Custom Domain Routing (Future)
```javascript
// Same logic, different domain
const subdomain = url.hostname.split('.')[0];
// ultrathink.apps.overskill.com → routes to production namespace
```

**The beauty: Code doesn't change, just the domain!**

## Decision Summary

✅ **Use workers.dev now** - Ship fast, test thoroughly
📅 **Plan custom domain for Month 2** - When ready for production
🚀 **Migration is easy** - Just update DNS and dispatch Worker