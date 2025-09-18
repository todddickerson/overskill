# Webhook handler for Supabase authentication events
class Webhooks::SupabaseController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook_signature

  def auth_event
    event_type = params[:type]
    record = params[:record]

    case event_type
    when "user.created"
      handle_user_created(record)
    when "user.updated"
      handle_user_update(record)
    when "user.deleted"
      handle_user_deletion(record)
    else
      Rails.logger.info "Unhandled Supabase event type: #{event_type}"
    end

    head :ok
  rescue => e
    Rails.logger.error "Supabase webhook error: #{e.message}"
    head :internal_server_error
  end

  private

  def verify_webhook_signature
    payload = request.body.read
    signature = request.headers["X-Supabase-Signature"]

    unless SupabaseService.instance.verify_webhook_signature(payload, signature)
      head :unauthorized
      return false
    end

    # Parse the body so params are available
    @_params = ActionController::Parameters.new(JSON.parse(payload))
  end

  def handle_user_created(supabase_user)
    # Check if user already exists with this Supabase ID
    return if User.exists?(supabase_user_id: supabase_user["id"])

    # Check if we have a Rails user with this email
    user = User.find_by(email: supabase_user["email"])

    if user
      # Link existing Rails user to Supabase user
      user.update!(
        supabase_user_id: supabase_user["id"],
        supabase_sync_status: "synced",
        supabase_last_synced_at: Time.current
      )
    else
      # Create new Rails user from Supabase user
      # This happens when user signs up through a generated app
      User.create!(
        email: supabase_user["email"],
        first_name: supabase_user.dig("user_metadata", "first_name"),
        last_name: supabase_user.dig("user_metadata", "last_name"),
        supabase_user_id: supabase_user["id"],
        supabase_sync_status: "synced",
        supabase_last_synced_at: Time.current,
        # Generate temporary password - user will use Supabase auth
        password: SecureRandom.hex(16),
        password_confirmation: SecureRandom.hex(16)
      )
    end
  end

  def handle_user_update(supabase_user)
    user = User.find_by(supabase_user_id: supabase_user["id"])
    return unless user

    # Only sync if email changed in Supabase
    if user.email != supabase_user["email"]
      user.update!(
        email: supabase_user["email"],
        supabase_last_synced_at: Time.current
      )
    end

    # Update metadata if changed
    if supabase_user["user_metadata"].present?
      metadata = supabase_user["user_metadata"]
      user.update!(
        first_name: metadata["first_name"] || user.first_name,
        last_name: metadata["last_name"] || user.last_name
      )
    end
  end

  def handle_user_deletion(supabase_user)
    user = User.find_by(supabase_user_id: supabase_user["id"])
    return unless user

    # Soft delete or handle according to business rules
    user.update!(
      supabase_user_id: nil,
      supabase_sync_status: "deleted",
      supabase_last_synced_at: Time.current
    )
  end
end
