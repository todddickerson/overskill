# Database Shards Configuration Guide

## Overview

OverSkill uses a multi-shard architecture to distribute AI-generated apps across multiple Supabase projects. Each shard can handle up to 10,000 apps with perfect isolation using Row Level Security (RLS).

## Configuration Methods

### 1. Environment Variables (Default Shard)

The easiest way to configure your first shard is through environment variables. Add these to your `.env` file:

```bash
# Required - Your existing Supabase credentials
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key

# Optional - Customize the default shard
SUPABASE_PROJECT_ID=your-project-id       # defaults to 'default-project'
DEFAULT_SHARD_NAME=main-shard             # defaults to 'default-shard' or 'development-shard'
```

The default shard will be automatically created:
- When the Rails application starts (via initializer)
- When running `rails db:seed`
- When running `rails shards:init_default`

### 2. Database Configuration (Additional Shards)

For additional shards, use the rake tasks or Rails console:

#### Using Rake Tasks

```bash
# List all shards
rails shards:list

# Add a new shard
rails shards:add[shard-002,https://xyz.supabase.co,anon_key,service_key,project_xyz]

# Update shard status
rails shards:update_status[shard-002,maintenance]

# Initialize default shard from ENV
rails shards:init_default

# Show configuration template
rails shards:config_template

# Sync all users to a specific shard
rails shards:sync_users[shard-002]
```

#### Using Rails Console

```ruby
# Create a new shard programmatically
DatabaseShard.create!(
  name: 'shard-002',
  shard_number: 2,
  supabase_project_id: 'project-002',
  supabase_url: 'https://xyz.supabase.co',
  supabase_anon_key: 'anon-key-002',
  supabase_service_key: 'service-key-002',
  app_count: 0,
  status: 'available'
)

# Find the current best shard for new apps
DatabaseShard.current_shard

# Check shard capacity
DatabaseShard.with_capacity.count
```

## Shard Statuses

- `provisioning` - Being set up, not ready for apps
- `available` - Ready to accept new apps
- `at_capacity` - Full (10,000 apps)
- `maintenance` - Temporarily unavailable
- `decommissioned` - No longer in use

## How Shards Are Used

### App Assignment

When a new app is created, it's automatically assigned to the shard with the most available capacity:

```ruby
class App < ApplicationRecord
  before_create :assign_to_shard
  
  private
  
  def assign_to_shard
    self.database_shard ||= DatabaseShard.current_shard
  end
end
```

### User Syncing

Users are synced to all available shards where their apps might be deployed:

```ruby
# Automatic sync on user creation/update
after_create :create_supabase_auth_user
after_update :sync_to_supabase_profile

# Manual sync to specific shard
rails shards:sync_users[shard-name]
```

## Best Practices

1. **Start with One Shard**: Use environment variables to configure your default shard. This is sufficient for the first 10,000 apps.

2. **Monitor Capacity**: Check shard usage regularly:
   ```bash
   rails shards:list
   ```

3. **Plan Ahead**: Add new shards before reaching capacity (around 9,000 apps).

4. **Use Descriptive Names**: Name shards clearly (e.g., 'us-west-001', 'europe-001').

5. **Keep Credentials Secure**: Never commit shard credentials to version control.

## Production Deployment

### On Heroku/Render

Set the required environment variables:
```bash
heroku config:set SUPABASE_URL=https://your-project.supabase.co
heroku config:set SUPABASE_ANON_KEY=your-anon-key
heroku config:set SUPABASE_SERVICE_KEY=your-service-key
heroku config:set DEFAULT_SHARD_NAME=production-primary
```

### Using Rails Credentials

For enhanced security, use Rails encrypted credentials:

```yaml
# config/credentials.yml.enc
supabase:
  default_shard:
    url: https://your-project.supabase.co
    anon_key: your-anon-key
    service_key: your-service-key
    project_id: your-project-id
  
  # Additional shards can be added here
  shard_002:
    url: https://shard2.supabase.co
    anon_key: shard2-anon-key
    service_key: shard2-service-key
```

Then update the initializer to use credentials:
```ruby
# config/initializers/database_shards.rb
creds = Rails.application.credentials.supabase&.default_shard
if creds
  ENV['SUPABASE_URL'] ||= creds[:url]
  ENV['SUPABASE_ANON_KEY'] ||= creds[:anon_key]
  ENV['SUPABASE_SERVICE_KEY'] ||= creds[:service_key]
end
```

## Monitoring

### Check Shard Health

```ruby
# In Rails console
DatabaseShard.all.map(&:usage_stats)

# Via rake task
rails shards:list
```

### Monitor User Sync

```ruby
# Check user shard mappings
user = User.find_by(email: 'user@example.com')
user.user_shard_mappings.includes(:database_shard)

# Check sync status
UserShardMapping.failed.count
UserShardMapping.synced.count
```

## Troubleshooting

### Missing Default Shard

If no default shard exists:
1. Check environment variables are set
2. Run `rails shards:init_default`
3. Or run `rails db:seed`

### Sync Failures

If users fail to sync to shards:
1. Check shard credentials are valid
2. Verify shard status is 'available'
3. Check Sidekiq for failed jobs
4. Review logs for specific errors

### Capacity Issues

When approaching shard capacity:
1. Add a new shard using rake task
2. New apps will automatically use the new shard
3. Existing apps remain on their assigned shard

## Example: Adding a Second Shard

```bash
# 1. Create new Supabase project at supabase.com

# 2. Add the shard to OverSkill
rails shards:add[us-west-002,https://newproject.supabase.co,anon_key_here,service_key_here,project_id_here]

# 3. Verify it was added
rails shards:list

# 4. Sync existing users (optional)
rails shards:sync_users[us-west-002]
```

That's it! New apps will automatically be distributed across available shards based on capacity.
