class Account::SupabaseSyncController < Account::ApplicationController
  # Only allow admin users to access this controller
  before_action :require_admin!
  
  def index
    @sync_stats = {
      total_users: User.count,
      synced_users: User.where(supabase_sync_status: 'synced').count,
      pending_users: User.where(supabase_user_id: nil).count,
      failed_users: User.where(supabase_sync_status: ['failed', 'error']).count,
      last_sync: User.where.not(supabase_last_synced_at: nil).maximum(:supabase_last_synced_at)
    }
    
    @recent_syncs = User.where.not(supabase_last_synced_at: nil)
                        .order(supabase_last_synced_at: :desc)
                        .limit(20)
    
    @failed_syncs = User.where(supabase_sync_status: ['failed', 'error'])
                        .order(updated_at: :desc)
                        .limit(10)
  end
  
  def sync_all
    # Queue background job to sync all users
    job = SyncUsersToSupabaseJob.perform_later
    
    respond_to do |format|
      format.html do
        redirect_to account_supabase_sync_index_path, 
                    notice: "Sync job queued. Job ID: #{job.job_id}"
      end
      format.json do
        render json: { 
          status: 'queued', 
          job_id: job.job_id,
          message: 'Sync job has been queued and will process users in batches.'
        }
      end
    end
  end
  
  def sync_user
    @user = User.find(params[:id])
    
    # Queue sync job for this specific user
    job = SupabaseAuthSyncJob.perform_later(@user, 'create')
    
    respond_to do |format|
      format.html do
        redirect_back(
          fallback_location: account_supabase_sync_index_path,
          notice: "Sync queued for #{@user.email}"
        )
      end
      format.json do
        render json: { 
          status: 'queued',
          job_id: job.job_id,
          user_id: @user.id
        }
      end
    end
  end
  
  def check_status
    # API endpoint to check sync status
    @user = User.find(params[:id])
    
    render json: {
      user_id: @user.id,
      email: @user.email,
      supabase_user_id: @user.supabase_user_id,
      sync_status: @user.supabase_sync_status,
      last_synced_at: @user.supabase_last_synced_at,
      synced: @user.supabase_user_id.present?
    }
  end
  
  def webhook_logs
    # Show recent webhook activity
    @webhook_logs = AppApiCall.where(endpoint: '/webhooks/supabase/auth')
                              .order(occurred_at: :desc)
                              .limit(50)
  end
  
  private
  
  def require_admin!
    unless can? :manage, User
      redirect_to account_dashboard_path, 
                  alert: "You don't have permission to access this page."
    end
  end
end