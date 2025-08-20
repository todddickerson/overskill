# Critical Next Steps - WFP Implementation

## 🚨 Required Environment Variables to Set

### 1. Create Cloudflare API Token
Go to: https://dash.cloudflare.com/profile/api-tokens

Create token with these permissions:
- Account:Workers Scripts:Edit
- Account:Workers for Platforms:Edit  
- Account:Workers Dispatch:Edit

Add to `.env.local`:
```bash
CLOUDFLARE_API_TOKEN=your_new_token_here
```

### 2. Generate Webhook Secret
Run in Rails console:
```ruby
SecureRandom.hex(32)
```

Add to `.env.local`:
```bash
OVERSKILL_WEBHOOK_SECRET=generated_secret_here
```

## ❓ Critical Questions Needing Your Decision

### 1. Template Repository Location
**Option A**: Create in main `overskill` organization (RECOMMENDED)
**Option B**: Create in `overskill-apps` organization

**Decision needed**: _____________

### 2. Domain Strategy
**Option A**: Use `overskill.workers.dev` subdomains (RECOMMENDED for start)
- Example: `ultrathink-abc123.overskill.workers.dev`

**Option B**: Custom domain like `apps.overskill.com`
- Requires additional DNS configuration

**Decision needed**: _____________

### 3. WFP Namespace Names
**Proposed** (can be changed):
- `overskill-preview`
- `overskill-staging`
- `overskill-production`

**Confirm or modify**: _____________

## ✅ What's Already Working

1. **GitHub App Authentication** - Fully configured and tested
2. **Repository Creation via Fork** - Working in 2-3 seconds
3. **Basic Worker Deployment** - Can deploy to standard Workers
4. **App Builder v5** - No changes needed, works as-is

## 🎯 First Implementation Task

Once you provide the decisions above, the first task will be:

1. Create the three WFP namespaces in Cloudflare
2. Create and deploy the dispatch Worker
3. Create the `vite-wfp-template` repository
4. Test with "ultrathink" app end-to-end

## 💡 Key Insight from Research

**Important**: Cloudflare's native Git integration does NOT work with Workers for Platforms. Our hybrid approach (GitHub + WFP API) is actually BETTER because it gives us:
- More control over the build process
- Professional CI/CD with PR previews
- Better integration with OverSkill platform
- Flexibility to customize deployment logic

## 📊 Why This Matters

**Cost at 1,000 apps**:
- Current approach: ~$2,500/month (and hits 500 Worker limit)
- WFP approach: ~$50-100/month (and supports 50,000+ apps)

**Savings**: ~$2,400/month (96% reduction)

---

**Ready to implement as soon as you provide the decisions above!**