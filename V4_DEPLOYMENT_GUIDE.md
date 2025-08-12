# V4 Deployment Guide
*Quick Start Guide for V4 App Generation and Deployment*

## 🚀 Prerequisites

### Required Environment Variables
Ensure these are set in your `.env.local`:

```bash
# Cloudflare (Required for deployment)
CLOUDFLARE_ACCOUNT_ID=your-cloudflare-account-id
CLOUDFLARE_ZONE_ID=your-zone-id  
CLOUDFLARE_API_TOKEN=your-api-token
CLOUDFLARE_EMAIL=your-cloudflare-email
CLOUDFLARE_R2_BUCKET=your-r2-bucket-name

# Supabase (Required for app functionality)
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key

# AI Services (Required for generation)
OPENROUTER_API_KEY=your-openrouter-key
ANTHROPIC_API_KEY=your-anthropic-key
```

### Verify Setup
```bash
# Run credential validation
ruby test_cloudflare_credentials.rb

# Expected output: ✅ All services initialized successfully!
```

## 📋 Quick Deployment Test

### 1. Simple Worker Deployment
```bash
# Test core deployment functionality
ruby test_simple_cloudflare_deployment.rb

# Expected: ✅ DEPLOYMENT SUCCESSFUL
```

### 2. Full V4 Flow Test  
```bash
# Test complete generation and deployment
ruby test_v4_deployment_flow.rb

# Expected: ✅ Vite Build SUCCESS, Worker deployed
```

### 3. Chat Feedback Test
```bash
# Test real-time chat system
ruby test_chat_feedback_system.rb

# Expected: ✅ ChatProgressBroadcaster working
```

## 🔧 V4 Generation Usage

### In Rails Console
```ruby
# Create a test app
user = User.create!(email: "test@example.com", password: "password123", 
                   first_name: "Test", last_name: "User")
team = Team.create!(name: "Test Team")
membership = team.memberships.create!(user: user, role: :admin)

app = team.apps.create!(
  name: "My V4 App",
  creator: membership,
  prompt: "Create a todo app with drag and drop"
)

# Generate with V4
message = app.app_chat_messages.create!(
  content: "Create a beautiful todo app with modern UI",
  user: user,
  role: "user"
)

# Start V4 generation with real-time feedback
builder = Ai::AppBuilderV4.new(message)
builder.execute!

# Check results
puts app.preview_url  # Should show Cloudflare Workers URL
puts app.status       # Should show 'generated' or 'deployed'
```

### Via Web Interface
1. Create new app
2. Enter app description 
3. Submit - watch real-time progress in chat
4. Get preview URL when complete
5. Test deployed app

## 🛠️ Build Process Details

### File Generation
V4 creates these core files:
- `package.json` - Dependencies and build scripts
- `vite.config.js` - Build configuration  
- `postcss.config.js` - CSS processing (minimal)
- `index.html` - App entry point
- `src/main.jsx` - React root
- `src/App.jsx` - Main React component
- Additional components as needed

### Build Pipeline
1. **File Creation**: AI generates React components
2. **Temp Directory**: Files written to isolated build env
3. **Vite Build**: Fast development build (~300-400ms)
4. **Worker Generation**: Converts to Cloudflare Workers format
5. **Deployment**: Uploads via Cloudflare API
6. **URL Generation**: Creates preview URL

## 🌐 Deployment Architecture

### Preview URLs
- Format: `https://worker-name.account-id.workers.dev`
- Instant global availability via Cloudflare network
- Automatic HTTPS and CDN

### Production URLs (Week 3)
- Custom domains via Cloudflare zones
- SSL certificate automation
- Advanced routing and caching

## 🔍 Troubleshooting

### Build Issues
```bash
# Check PostCSS config
# Should have minimal config in temp directory

# Verify Vite build
cd tmp/builds/app_[id]_[timestamp]
npm run build:preview
```

### Deployment Issues  
```bash
# Test credentials
ruby test_cloudflare_credentials.rb

# Check API permissions
# API token needs: Workers:Edit, Zone:Read permissions
```

### Chat Feedback Issues
```bash
# Test broadcaster
ruby test_chat_feedback_system.rb

# Check ActionCable setup
# Ensure Redis is running for real-time updates
```

## 📊 Performance Expectations

### Build Times
- **Fast Preview**: 300-500ms
- **Full Production**: 2-5 seconds (Week 3)
- **File Generation**: 1-3 seconds per component

### Deployment Times
- **Worker Upload**: 1-2 seconds
- **Global Propagation**: 10-30 seconds
- **DNS Resolution**: 2-5 minutes for new workers

### Chat Updates
- **Progress Messages**: Real-time (<100ms)
- **File Notifications**: Instant
- **Completion**: Immediate with preview URL

## 🚨 Known Limitations

### Current (Week 2 Complete)
- ✅ Basic deployment working
- ⚠️ Secrets API needs token permissions
- ⚠️ No custom domains yet
- ⚠️ Preview-only deployments

### Week 3 Targets
- Custom domain routing
- Production optimization  
- Advanced secrets management
- SSL certificate automation

## 📞 Support

### Test Your Setup
Run all validation tests:
```bash
ruby test_cloudflare_credentials.rb
ruby test_chat_feedback_system.rb  
ruby test_simple_cloudflare_deployment.rb
```

All should show ✅ success indicators.

### Debug Mode
Enable verbose logging:
```bash
VERBOSE_AI_LOGGING=true
RAILS_LOG_LEVEL=debug
```

### Key Services
- `Ai::AppBuilderV4` - Main orchestrator
- `Ai::ChatProgressBroadcaster` - Real-time feedback
- `Deployment::CloudflareWorkersDeployer` - Worker deployment
- `Deployment::ExternalViteBuilder` - Build system

---

**V4 is ready for production app generation and deployment! 🎉**