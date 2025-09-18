# Background job to sync existing Rails users to Supabase
class SyncUsersToSupabaseJob < ApplicationJob
  queue_as :low_priority

  def perform(batch_size: 50)
    Rails.logger.info "[SyncUsersToSupabase] Starting user sync process"

    # Process users in batches to avoid overwhelming the API
    users_to_sync = User.where(supabase_user_id: nil)
      .or(User.where(supabase_sync_status: ["pending", "failed"]))
      .limit(batch_size)

    synced_count = 0
    failed_count = 0

    users_to_sync.find_each do |user|
      result = sync_user(user)

      if result[:success]
        synced_count += 1
      else
        failed_count += 1
        Rails.logger.error "[SyncUsersToSupabase] Failed to sync user #{user.id}: #{result[:error]}"
      end

      # Rate limiting - avoid hitting API limits
      sleep 0.1
    end

    Rails.logger.info "[SyncUsersToSupabase] Sync complete. Synced: #{synced_count}, Failed: #{failed_count}"

    # Schedule next batch if there are more users to sync
    remaining_count = User.where(supabase_user_id: nil).count
    if remaining_count > 0
      Rails.logger.info "[SyncUsersToSupabase] #{remaining_count} users remaining. Scheduling next batch..."
      SyncUsersToSupabaseJob.set(wait: 5.minutes).perform_later(batch_size: batch_size)
    end
  end

  private

  def sync_user(user)
    Rails.logger.info "[SyncUsersToSupabase] Syncing user #{user.id} (#{user.email})"

    # Skip if already synced recently
    if user.supabase_user_id.present? && user.supabase_last_synced_at && user.supabase_last_synced_at > 1.hour.ago
      Rails.logger.info "[SyncUsersToSupabase] User #{user.id} already synced recently, skipping"
      return {success: true}
    end

    # Create or update user in Supabase
    result = if user.supabase_user_id.present?
      # Update existing Supabase user
      SupabaseService.instance.update_user(
        user.supabase_user_id,
        {
          email: user.email,
          user_metadata: build_user_metadata(user)
        }
      )
    else
      # Create new Supabase user
      SupabaseService.instance.create_user(
        user.email,
        nil, # Let Supabase generate secure password
        build_user_metadata(user)
      )
    end

    if result[:success]
      # Update Rails user with Supabase ID
      supabase_user = result[:data]
      user.update!(
        supabase_user_id: supabase_user["id"],
        supabase_sync_status: "synced",
        supabase_last_synced_at: Time.current
      )

      # Create or update profile in Supabase
      profile_result = SupabaseService.instance.create_profile(user)

      if profile_result[:success]
        Rails.logger.info "[SyncUsersToSupabase] Successfully synced user #{user.id}"
        {success: true}
      else
        Rails.logger.error "[SyncUsersToSupabase] Failed to create profile for user #{user.id}: #{profile_result[:error]}"
        user.update(supabase_sync_status: "profile_failed")
        {success: false, error: profile_result[:error]}
      end
    else
      user.update(
        supabase_sync_status: "failed",
        supabase_last_synced_at: Time.current
      )
      {success: false, error: result[:error]}
    end
  rescue => e
    Rails.logger.error "[SyncUsersToSupabase] Exception syncing user #{user.id}: #{e.message}"
    user.update(supabase_sync_status: "error")
    {success: false, error: e.message}
  end

  def build_user_metadata(user)
    {
      rails_user_id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      name: user.name,
      team_id: user.current_team&.id,
      team_name: user.current_team&.name,
      created_via: "rails_sync",
      synced_at: Time.current.iso8601
    }
  end
end
