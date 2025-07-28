# OverSkill Deployment Guide

## Overview

OverSkill consists of three main components that need to be deployed:
1. Rails application (control plane)
2. Cloudflare Workers (app hosting)
3. Background job processors

## Prerequisites

- Ruby 3.2.0+
- PostgreSQL 14+
- Redis 7+
- Cloudflare account
- Stripe account
- OpenRouter API key

## Development Setup

```bash
# Clone repository
git clone https://github.com/yourusername/overskill.git
cd overskill

# Run setup script
bin/overskill-setup

# Configure environment
cp .env.example .env
# Edit .env with your credentials

# Start development server
bin/dev
```

## Production Deployment

### Option 1: Render.com (Recommended)

1. **Fork the repository** to your GitHub account

2. **Create Render account** at https://render.com

3. **Create services:**
   - Web Service (Rails app)
   - PostgreSQL database
   - Redis instance
   - Background Worker (Sidekiq)

4. **Configure environment variables** in Render dashboard

5. **Deploy:**
   ```yaml
   # render.yaml is already configured
   - Just connect GitHub repo
   - Render auto-deploys on push
   ```

### Option 2: Railway

1. **Install Railway CLI:**
   ```bash
   npm install -g @railway/cli
   ```

2. **Login and initialize:**
   ```bash
   railway login
   railway init
   ```

3. **Add services:**
   ```bash
   railway add postgresql
   railway add redis
   ```

4. **Deploy:**
   ```bash
   railway up
   ```

### Option 3: Heroku

1. **Create Heroku app:**
   ```bash
   heroku create overskill-app
   ```

2. **Add addons:**
   ```bash
   heroku addons:create heroku-postgresql:standard-0
   heroku addons:create heroku-redis:premium-0
   ```

3. **Configure:**
   ```bash
   heroku config:set RAILS_MASTER_KEY=$(cat config/master.key)
   # Set other environment variables
   ```

4. **Deploy:**
   ```bash
   git push heroku main
   heroku run rails db:migrate
   ```

## Cloudflare Setup

### 1. R2 Storage

```bash
# Install Wrangler CLI
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Create R2 bucket
wrangler r2 bucket create overskill-apps
```

### 2. Workers Configuration

Create `wrangler.toml`:
```toml
name = "overskill-apps"
main = "src/index.js"
compatibility_date = "2024-01-01"

[[r2_buckets]]
binding = "R2_BUCKET"
bucket_name = "overskill-apps"

[env.production]
routes = [
  { pattern = "*.overskill.app", zone_name = "overskill.app" }
]
```

Deploy worker:
```bash
wrangler deploy
```

### 3. DNS Configuration

In Cloudflare dashboard:
```
Type: CNAME
Name: *
Target: overskill-apps.workers.dev
Proxy: Enabled
```

## Database Setup

### Production Migrations

```bash
# Run on deployment
rails db:migrate

# Seed initial data
rails db:seed:production
```

### Backup Configuration

```ruby
# config/initializers/backup.rb
if Rails.env.production?
  # Daily backups to S3
  Backup::Model.new(:daily_backup, 'Daily Backup') do
    database PostgreSQL do |db|
      db.name = ENV['DATABASE_NAME']
      db.username = ENV['DATABASE_USER']
      db.password = ENV['DATABASE_PASSWORD']
    end
    
    store_with S3 do |s3|
      s3.access_key_id = ENV['AWS_ACCESS_KEY_ID']
      s3.secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
      s3.bucket = 'overskill-backups'
    end
    
    compress_with Gzip
  end
end
```

## Environment Variables

### Required for Production

```bash
# Rails
RAILS_ENV=production
SECRET_KEY_BASE=generate-with-rails-secret

# Database
DATABASE_URL=postgresql://user:pass@host/db

# Redis
REDIS_URL=redis://user:pass@host:6379

# AI
OPENROUTER_API_KEY=sk-or-v1-xxx

# Cloudflare
CLOUDFLARE_API_KEY=xxx
CLOUDFLARE_ACCOUNT_ID=xxx
CLOUDFLARE_R2_ACCESS_KEY_ID=xxx
CLOUDFLARE_R2_SECRET_ACCESS_KEY=xxx

# Stripe
STRIPE_PUBLISHABLE_KEY=pk_live_xxx
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx

# Email
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=SG.xxx

# Application
APP_HOST=overskill.app
FORCE_SSL=true
```

## Monitoring Setup

### 1. Application Monitoring

```ruby
# Gemfile
gem 'skylight' # or 'newrelic_rpm'

# config/skylight.yml
production:
  authentication: YOUR_SKYLIGHT_TOKEN
```

### 2. Error Tracking

```ruby
# config/initializers/sentry.rb
Sentry.init do |config|
  config.dsn = ENV['SENTRY_DSN']
  config.breadcrumbs_logger = [:active_support_logger]
end
```

### 3. Uptime Monitoring

- Configure UptimeRobot or Pingdom
- Monitor endpoints:
  - `https://overskill.app/health`
  - `https://api.overskill.app/health`

## Performance Optimization

### 1. Asset Compilation

```bash
# Precompile assets
RAILS_ENV=production rails assets:precompile

# Clean old assets
RAILS_ENV=production rails assets:clean
```

### 2. Database Indexes

```ruby
# Ensure all foreign keys have indexes
rails g migration AddMissingIndexes

# In migration
add_index :apps, [:status, :visibility, :created_at]
add_index :purchases, [:user_id, :created_at]
# etc.
```

### 3. Caching

```ruby
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV['REDIS_URL'],
  expires_in: 1.hour
}
```

## Deployment Checklist

- [ ] Environment variables configured
- [ ] Database migrated
- [ ] Assets compiled
- [ ] SSL certificates active
- [ ] Monitoring configured
- [ ] Backups scheduled
- [ ] Error tracking active
- [ ] Email sending verified
- [ ] Payment processing tested
- [ ] Cloudflare Workers deployed

## Rollback Procedure

```bash
# Render/Railway
# Use dashboard to rollback to previous deployment

# Heroku
heroku rollback

# Manual
git revert HEAD
git push origin main
```

## Scaling

### Horizontal Scaling

```bash
# Render
# Adjust instance count in dashboard

# Railway
railway scale --count 3

# Heroku
heroku ps:scale web=3 worker=2
```

### Database Scaling

- Add read replicas for heavy read loads
- Use pgbouncer for connection pooling
- Consider partitioning large tables

## Security Hardening

### 1. Headers

```ruby
# config/application.rb
config.force_ssl = true
config.ssl_options = { hsts: { subdomains: true } }
```

### 2. Secrets

```bash
# Never commit secrets
# Use Rails credentials
EDITOR=vim rails credentials:edit
```

### 3. Dependencies

```bash
# Regular updates
bundle update --conservative
yarn upgrade-interactive
```

## Troubleshooting

### Common Issues

1. **Assets not loading**
   - Check `RAILS_SERVE_STATIC_FILES=true`
   - Verify CDN configuration

2. **Database connection errors**
   - Check `DATABASE_URL` format
   - Verify connection pool settings

3. **Background jobs not running**
   - Ensure Sidekiq is deployed
   - Check Redis connection

### Debug Commands

```bash
# Rails console
heroku run rails console

# Logs
heroku logs --tail

# Database console
heroku pg:psql
```

## Support

- Documentation: https://docs.overskill.app
- Status Page: https://status.overskill.app
- Support: support@overskill.app

---

For detailed platform-specific instructions, see:
- [Render Guide](https://render.com/docs)
- [Railway Guide](https://docs.railway.app)
- [Heroku Guide](https://devcenter.heroku.com)
