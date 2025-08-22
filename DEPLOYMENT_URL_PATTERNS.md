# Deployment URL Patterns

## GitHub Actions + Workers for Platforms (WFP) Deployment

### Primary Deployment Method
- **GitHub Actions Workflow**: Main deployment pipeline
- **Workers for Platforms**: Deployment target using dispatch namespaces

### URL Format for Deployed Apps

#### Preview Environment
```
https://preview-{app_id}.overskill.app
```
Example: `https://preview-jaqdoj.overskill.app`

#### Production Environment
```
https://{app_id}.overskill.app
```
Example: `https://jaqdoj.overskill.app`

### Important Notes

1. **NOT workers.dev subdomains**: Apps do NOT use `.workers.dev` URLs
   - ❌ WRONG: `hello-world-showcase-jaqdoj-preview.overskill-development-preview.workers.dev`
   - ✅ CORRECT: `https://preview-jaqdoj.overskill.app`

2. **App ID**: The unique 6-character ID generated for each app (e.g., "jaqdoj")
   - Found in: `VITE_APP_ID` environment variable
   - Used in: Script names and URLs

3. **Namespace Pattern**: `overskill-{rails_env}-{environment}`
   - Preview: `overskill-development-preview`
   - Production: `overskill-development-production`

### Deployment Workflow

1. **GitHub Push** → Triggers workflow in `.github/workflows/deploy.yml`
2. **Build Process** → `npm install && npm run build`
3. **WFP Deployment** → Uploads to Cloudflare dispatch namespace
4. **URL Generation** → `https://preview-{app_id}.overskill.app`

### How to Verify URLs

```bash
# Check if URL is accessible
curl -I https://preview-{app_id}.overskill.app

# Expected response
HTTP/2 200 
content-type: text/html; charset=utf-8
```

### Database Fields

When setting URLs in the database:
```ruby
app.preview_url = "https://preview-#{app_id}.overskill.app"
app.production_url = "https://#{app_id}.overskill.app"  # When deployed to production
```

### Common Mistakes to Avoid

1. **Using full app name in URL**: The URL uses the 6-char app_id, not the full name
2. **Including workers.dev domain**: All apps use overskill.app domain
3. **Wrong namespace format**: Remember the Rails environment is part of namespace name
4. **Missing "preview-" prefix**: Preview URLs must include the prefix

### GitHub Actions Deployment Triggers

- **Preview**: Automatic on push to main branch
- **Production**: Only when commit message contains `[deploy:production]` or `[production]`

### Checking Deployment Status

```bash
# View recent workflow runs
gh run list --repo Overskill-apps/{repo-name} --limit 5

# Check workflow status
gh run view {run-id} --repo Overskill-apps/{repo-name}
```