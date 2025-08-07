# OverSkill AI App Builder - Operations Guide

## 📋 Table of Contents
1. [System Requirements](#system-requirements)
2. [Deployment](#deployment)
3. [Configuration](#configuration)
4. [Monitoring](#monitoring)
5. [Maintenance](#maintenance)
6. [Troubleshooting](#troubleshooting)
7. [Performance Optimization](#performance-optimization)
8. [Security](#security)

---

## 🖥️ System Requirements

### Minimum Requirements
- **Ruby**: 3.3.0+
- **Rails**: 8.0.2+
- **PostgreSQL**: 14+
- **Redis**: 6.2+ (for caching)
- **Node.js**: 18+
- **Memory**: 4GB RAM
- **Storage**: 20GB available

### Recommended Production Setup
- **CPU**: 4+ cores
- **Memory**: 8GB+ RAM
- **Storage**: 100GB SSD
- **Redis**: Dedicated instance
- **CDN**: Cloudflare

---

## 🚀 Deployment

### 1. Environment Setup

```bash
# Clone repository
git clone https://github.com/your-org/overskill.git
cd overskill

# Install dependencies
bundle install
yarn install

# Setup database
rails db:create
rails db:migrate
rails db:seed
```

### 2. Environment Variables

```bash
# .env.production
# AI Services
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPENROUTER_API_KEY=sk-or-...

# Redis
REDIS_URL=redis://localhost:6379/0

# Database
DATABASE_URL=postgresql://user:pass@localhost/overskill_production

# Cloudflare (for deployment)
CLOUDFLARE_ACCOUNT_ID=...
CLOUDFLARE_API_TOKEN=...

# Analytics
GOOGLE_ANALYTICS_ID=G-...

# Image Generation (optional)
STABILITY_API_KEY=...
REPLICATE_API_TOKEN=...
```

### 3. Production Deployment

```bash
# Precompile assets
RAILS_ENV=production rails assets:precompile

# Run migrations
RAILS_ENV=production rails db:migrate

# Start services
RAILS_ENV=production puma -C config/puma.rb

# Start Sidekiq for background jobs
RAILS_ENV=production bundle exec sidekiq
```

### 4. Docker Deployment

```dockerfile
# Dockerfile
FROM ruby:3.3.0

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

RUN rails assets:precompile

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

```bash
# Build and run
docker build -t overskill .
docker run -p 3000:3000 --env-file .env.production overskill
```

---

## ⚙️ Configuration

### 1. AI Model Configuration

```ruby
# config/ai_models.yml
production:
  primary_model: "anthropic/claude-3.5-sonnet"
  fallback_model: "openrouter/kimi-k2"
  image_model: "openai/dall-e-3"
  
  cache_settings:
    ttl: 300 # 5 minutes
    max_size: 100MB
    
  rate_limits:
    requests_per_minute: 60
    tokens_per_minute: 100000
```

### 2. Tool Configuration

```ruby
# config/tools.yml
enabled_tools:
  - read_file
  - write_file
  - update_file
  - line_replace
  - delete_file
  - rename_file
  - search_files
  - read_console_logs
  - read_network_requests
  - add_dependency
  - remove_dependency
  - web_search
  - download_to_repo
  - fetch_website
  - broadcast_progress
  - generate_image
  - edit_image
  - read_analytics
  - git_status
  - git_commit
  - git_branch
  - git_diff
  - git_log

tool_limits:
  max_file_size: 10MB
  max_search_results: 100
  max_image_size: 2048x2048
```

### 3. Caching Configuration

```ruby
# config/cache.yml
production:
  redis:
    url: <%= ENV['REDIS_URL'] %>
    pool_size: 10
    timeout: 5
    
  cache_levels:
    global:
      ttl: 3600 # 1 hour
      keys:
        - system_prompts
        - ai_standards
        
    tenant:
      ttl: 1800 # 30 minutes
      keys:
        - user_context
        - app_schema
        
    file:
      ttl: 600 # 10 minutes
      keys:
        - file_contents
        - file_metadata
```

---

## 📊 Monitoring

### 1. Application Monitoring

```ruby
# config/initializers/monitoring.rb
if Rails.env.production?
  # APM setup
  require 'newrelic_rpm' if defined?(NewRelic)
  
  # Error tracking
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.breadcrumbs_logger = [:active_support_logger]
  end
end
```

### 2. Key Metrics to Monitor

#### System Metrics
- **CPU Usage**: Target < 70%
- **Memory Usage**: Target < 80%
- **Disk I/O**: Monitor for spikes
- **Network Latency**: < 100ms

#### Application Metrics
- **Response Time**: P95 < 1s
- **Error Rate**: < 1%
- **Cache Hit Rate**: > 60%
- **AI Token Usage**: Track daily

#### Business Metrics
- **Apps Created**: Daily/Weekly
- **AI Requests**: Per user/app
- **Tool Usage**: Most/least used
- **Cost per App**: AI + Infrastructure

### 3. Monitoring Commands

```bash
# Check system status
rails overskill:status

# View cache statistics
rails overskill:cache:stats

# Check AI usage
rails overskill:ai:usage

# View tool usage
rails overskill:tools:stats
```

---

## 🔧 Maintenance

### 1. Daily Tasks

```bash
# Check system health
curl http://localhost:3000/health

# Review error logs
tail -f log/production.log | grep ERROR

# Check Redis memory
redis-cli INFO memory

# Monitor Sidekiq
bundle exec sidekiq-status
```

### 2. Weekly Tasks

```bash
# Database maintenance
rails db:maintenance:vacuum
rails db:maintenance:analyze

# Clear old cache
rails overskill:cache:cleanup

# Backup database
pg_dump overskill_production > backup_$(date +%Y%m%d).sql

# Update dependencies (test first)
bundle update --conservative
```

### 3. Monthly Tasks

```bash
# Full system backup
rails overskill:backup:full

# Security updates
bundle audit check --update
yarn audit fix

# Performance analysis
rails overskill:performance:report

# Cost analysis
rails overskill:cost:report
```

---

## 🐛 Troubleshooting

### Common Issues

#### 1. High Memory Usage
```bash
# Check memory consumers
ps aux | sort -nrk 4 | head

# Clear Redis cache
redis-cli FLUSHDB

# Restart services
systemctl restart puma
systemctl restart sidekiq
```

#### 2. Slow AI Responses
```bash
# Check cache hit rate
rails overskill:cache:stats

# Verify API keys
rails overskill:ai:test

# Switch to fallback model
rails overskill:ai:switch_model fallback
```

#### 3. Git Integration Issues
```bash
# Check Git repos
ls -la tmp/repos/

# Clean orphaned repos
rails overskill:git:cleanup

# Reset Git service
rails overskill:git:reset
```

#### 4. Analytics Not Working
```bash
# Check Redis connection
redis-cli PING

# Verify analytics service
rails overskill:analytics:test

# Rebuild analytics cache
rails overskill:analytics:rebuild
```

### Debug Mode

```ruby
# Enable debug logging
Rails.logger.level = :debug

# Enable SQL logging
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Enable AI request logging
ENV['AI_DEBUG'] = 'true'
```

---

## ⚡ Performance Optimization

### 1. Database Optimization

```sql
-- Add indexes for common queries
CREATE INDEX idx_apps_team_id ON apps(team_id);
CREATE INDEX idx_app_files_app_id ON app_files(app_id);
CREATE INDEX idx_messages_app_id ON app_chat_messages(app_id);

-- Analyze tables
ANALYZE apps;
ANALYZE app_files;
ANALYZE app_chat_messages;
```

### 2. Redis Optimization

```bash
# config/redis.conf
maxmemory 2gb
maxmemory-policy allkeys-lru
save 900 1
save 300 10
save 60 10000
```

### 3. AI Optimization

```ruby
# Batch requests when possible
def batch_ai_requests(messages)
  messages.in_groups_of(5).map do |group|
    Thread.new { process_group(group) }
  end.map(&:value)
end

# Use streaming for large responses
def stream_ai_response(prompt)
  client.chat_stream(prompt) do |chunk|
    yield chunk
  end
end
```

### 4. Caching Strategy

```ruby
# Cache expensive operations
def expensive_operation
  Rails.cache.fetch("expensive_#{params}", expires_in: 1.hour) do
    # Expensive computation
  end
end

# Use Russian doll caching
cache @app do
  cache @app.files do
    render files
  end
end
```

---

## 🔒 Security

### 1. API Security

```ruby
# Rate limiting
Rack::Attack.throttle('api/ip', limit: 300, period: 5.minutes) do |req|
  req.ip if req.path.start_with?('/api')
end

# API authentication
before_action :authenticate_api_key!

def authenticate_api_key!
  api_key = request.headers['X-API-Key']
  return if valid_api_key?(api_key)
  render json: { error: 'Unauthorized' }, status: 401
end
```

### 2. Data Security

```ruby
# Encrypt sensitive data
class App < ApplicationRecord
  encrypts :api_keys
  encrypts :credentials
end

# Sanitize user input
def sanitize_prompt(prompt)
  ActionController::Base.helpers.sanitize(prompt)
end
```

### 3. Infrastructure Security

```bash
# Firewall rules
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw default deny incoming

# SSL/TLS
certbot --nginx -d overskill.app

# Regular updates
apt update && apt upgrade -y
```

---

## 📈 Scaling

### Horizontal Scaling

```yaml
# docker-compose.yml
version: '3'
services:
  web:
    image: overskill
    scale: 3
    
  sidekiq:
    image: overskill
    command: sidekiq
    scale: 2
    
  redis:
    image: redis:alpine
    
  postgres:
    image: postgres:14
```

### Load Balancing

```nginx
upstream overskill {
  server app1.overskill.app;
  server app2.overskill.app;
  server app3.overskill.app;
}

server {
  location / {
    proxy_pass http://overskill;
  }
}
```

---

## 📞 Support

### Logging

```ruby
# Structured logging
Rails.logger.info({
  event: 'ai_request',
  user_id: current_user.id,
  app_id: app.id,
  tool: tool_name,
  duration: duration
}.to_json)
```

### Health Checks

```ruby
# app/controllers/health_controller.rb
class HealthController < ApplicationController
  def check
    checks = {
      database: check_database,
      redis: check_redis,
      ai_service: check_ai_service
    }
    
    status = checks.values.all? ? :ok : :service_unavailable
    render json: checks, status: status
  end
end
```

### Metrics Endpoint

```ruby
# /metrics
def metrics
  render json: {
    apps_created_today: App.where('created_at > ?', 1.day.ago).count,
    active_users: User.where('last_seen_at > ?', 1.hour.ago).count,
    cache_hit_rate: cache_hit_rate,
    ai_tokens_used: ai_tokens_today,
    tool_usage: tool_usage_stats
  }
end
```

---

## 🔄 Backup & Recovery

### Automated Backups

```bash
# /etc/cron.d/overskill-backup
0 2 * * * postgres pg_dump overskill_production | gzip > /backups/db_$(date +\%Y\%m\%d).sql.gz
0 3 * * * redis redis-cli BGSAVE
0 4 * * * tar -czf /backups/files_$(date +\%Y\%m\%d).tar.gz /app/tmp/repos
```

### Recovery Procedures

```bash
# Database recovery
gunzip < backup.sql.gz | psql overskill_production

# Redis recovery
redis-cli FLUSHALL
redis-cli --rdb /backups/dump.rdb

# File recovery
tar -xzf files_backup.tar.gz -C /
```

---

## 📚 Additional Resources

- **Documentation**: `/docs` directory
- **API Reference**: `/api/documentation`
- **Support**: support@overskill.app
- **Status Page**: status.overskill.app
- **Changelog**: `/CHANGELOG.md`

---

*Last Updated: August 7, 2025*
*Version: 3.0*