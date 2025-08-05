# Supabase Integration Documentation

## Overview

OverSkill uses a hybrid authentication architecture that maintains Rails (Devise) as the primary auth system while syncing users to Supabase for generated app authentication. This allows us to leverage Rails' mature auth ecosystem while providing modern real-time features to generated apps.

## Architecture

### Phase 1: Core Setup (✅ Completed)
- Database fields added to User model (`supabase_user_id`, `supabase_sync_status`, etc.)
- `SupabaseService` singleton for API communication
- Webhook handler for bidirectional sync
- Supabase API client integration

### Phase 2: User Sync (✅ Completed)
- Automatic sync on user lifecycle events (create/update/delete)
- Batch sync for existing users
- OAuth provider mapping
- Admin monitoring dashboard

### Phase 3: App Integration (🚧 Next)
- Per-app Supabase project configuration
- JWT token exchange between Rails and Supabase
- Real-time database features for generated apps
- App-specific user management

## Implementation Details

### 1. User Model Integration

The User model has Supabase sync fields:
```ruby
# app/models/user.rb
class User < ApplicationRecord
  # Supabase fields:
  # - supabase_user_id (string) - UUID from Supabase
  # - supabase_sync_status (string) - synced/pending/failed/error/deleted
  # - supabase_last_synced_at (datetime) - Last successful sync
  
  # Callbacks for automatic sync
  after_create :create_supabase_auth_user
  after_update :sync_to_supabase_profile, if: :should_sync_to_supabase?
end
```

### 2. Sync Services

#### SupabaseService (Singleton)
Main API client for Supabase operations:
```ruby
# app/services/supabase_service.rb
SupabaseService.instance.create_user(email, password, metadata)
SupabaseService.instance.update_user(supabase_id, attributes)
SupabaseService.instance.create_profile(user)
SupabaseService.instance.delete_user(supabase_id)
```

#### Background Jobs
- **SyncUsersToSupabaseJob**: Batch processes existing users with rate limiting
- **SupabaseAuthSyncJob**: Real-time sync for individual user events
- Both include retry logic and error handling

#### OAuth Integration
`SupabaseOauthSyncService` maps Rails OAuth providers to Supabase:
- google_oauth2 → google
- github → github
- facebook → facebook
- etc.

### 3. Admin Dashboard

Located at `/account/supabase_sync` (admin only):
- Sync statistics (total, synced, pending, failed)
- Recent sync activity
- Failed sync management with retry
- Webhook logs
- Manual sync triggers

### 4. Webhook Integration

Handles Supabase events at `/webhooks/supabase/auth_event`:
- user.created - Links Supabase users to Rails
- user.updated - Syncs email/metadata changes
- user.deleted - Soft deletes in Rails

Webhook signature verification ensures security.

### 5. Rake Tasks

Management commands:
```bash
# Sync all pending users
rake supabase:sync_all_users

# Check current sync status
rake supabase:sync_status

# Sync specific user by email
rake supabase:sync_user[user@example.com]

# Generate webhook secret
rake supabase:generate_webhook_secret

# Reset all sync status (danger!)
rake supabase:reset_sync
```

## Usage Patterns

### When to Use Supabase Sync

1. **New User Registration**
   - Automatically creates Supabase user via callback
   - Sends password setup email for Supabase auth

2. **User Profile Updates**
   - Email changes sync automatically
   - Name/metadata updates sync in real-time

3. **OAuth Login**
   - Creates Supabase user with OAuth identity
   - Links provider accounts between systems

4. **User Deletion**
   - Soft deletes in Supabase (marks inactive)
   - Preserves audit trail

### When NOT to Use Supabase

1. **Admin Authentication**
   - Keep using Rails/Devise for admin panel
   - More secure and feature-rich

2. **Team Management**
   - BulletTrain's team system stays in Rails
   - Supabase only for generated app users

3. **Billing/Subscriptions**
   - Stripe integration remains Rails-only
   - Supabase users get mapped to Rails for billing

## Security Considerations

1. **Webhook Verification**
   - HMAC signature validation
   - Shared secret in SUPABASE_WEBHOOK_SECRET

2. **Password Handling**
   - Supabase generates secure passwords
   - Users set passwords via email link
   - No password sync between systems

3. **Soft Deletes**
   - Users marked inactive, not deleted
   - Preserves data integrity
   - Complies with data retention policies

## Troubleshooting

### Common Issues

1. **Sync Failures**
   - Check Sidekiq for job errors
   - Verify API keys are correct
   - Check rate limits

2. **Webhook Errors**
   - Ensure webhook secret matches
   - Check webhook URL in Supabase dashboard
   - Verify Rails route is accessible

3. **OAuth Sync Issues**
   - Confirm provider mapping is correct
   - Check OAuth app configurations
   - Verify metadata is being passed

### Monitoring

- Admin dashboard: `/account/supabase_sync`
- Sidekiq dashboard: `/sidekiq`
- Rails logs: `tail -f log/development.log`
- API calls: Check AppApiCall records

## Future Enhancements

### Phase 3 Implementation
1. Per-app Supabase projects
2. JWT token exchange
3. Real-time subscriptions
4. Row-level security

### Potential Features
- Automatic Supabase project creation
- Migration tools for app data
- Analytics integration
- Edge function deployment