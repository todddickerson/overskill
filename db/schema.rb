# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_08_05_200810) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "account_onboarding_invitation_lists", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.jsonb "invitations"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_account_onboarding_invitation_lists_on_team_id"
  end

  create_table "action_mailbox_inbound_emails", force: :cascade do |t|
    t.integer "status", default: 0, null: false
    t.string "message_id", null: false
    t.string "message_checksum", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id", "message_checksum"], name: "index_action_mailbox_inbound_emails_uniqueness", unique: true
  end

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", precision: nil, null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", precision: nil, null: false
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "addresses", force: :cascade do |t|
    t.string "addressable_type", null: false
    t.bigint "addressable_id", null: false
    t.string "address_one"
    t.string "address_two"
    t.string "city"
    t.integer "region_id"
    t.string "region_name"
    t.integer "country_id"
    t.string "postal_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["addressable_type", "addressable_id"], name: "index_addresses_on_addressable"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.bigint "visit_id"
    t.bigint "user_id"
    t.bigint "team_id"
    t.string "name"
    t.jsonb "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["properties"], name: "index_ahoy_events_on_properties", opclass: :jsonb_path_ops, using: :gin
    t.index ["team_id"], name: "index_ahoy_events_on_team_id"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
    t.index ["visit_id"], name: "index_ahoy_events_on_visit_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.bigint "user_id"
    t.bigint "team_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.index ["team_id"], name: "index_ahoy_visits_on_team_id"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "app_api_calls", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "http_method"
    t.string "path"
    t.integer "status_code"
    t.integer "response_time"
    t.text "request_body"
    t.text "response_body"
    t.string "user_agent"
    t.string "ip_address"
    t.datetime "occurred_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "occurred_at"], name: "index_app_api_calls_on_app_id_and_occurred_at"
    t.index ["app_id"], name: "index_app_api_calls_on_app_id"
    t.index ["http_method"], name: "index_app_api_calls_on_http_method"
    t.index ["occurred_at"], name: "index_app_api_calls_on_occurred_at"
    t.index ["status_code"], name: "index_app_api_calls_on_status_code"
  end

  create_table "app_api_integrations", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "name"
    t.string "base_url"
    t.string "auth_type"
    t.string "api_key"
    t.string "path_prefix"
    t.text "additional_headers"
    t.boolean "enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_api_integrations_on_app_id"
  end

  create_table "app_chat_messages", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.text "content"
    t.string "role"
    t.text "response"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.bigint "app_version_id"
    t.jsonb "metadata", default: {}
    t.index ["app_id", "created_at"], name: "index_app_chat_messages_on_app_id_and_created_at"
    t.index ["app_id"], name: "index_app_chat_messages_on_app_id"
    t.index ["app_version_id"], name: "index_app_chat_messages_on_app_version_id"
    t.index ["created_at"], name: "index_app_chat_messages_on_created_at"
    t.index ["metadata"], name: "index_app_chat_messages_on_metadata", using: :gin
    t.index ["status"], name: "index_app_chat_messages_on_status"
    t.index ["user_id"], name: "index_app_chat_messages_on_user_id"
    t.check_constraint "role::text = 'assistant'::text AND (status::text = ANY (ARRAY['planning'::character varying, 'executing'::character varying, 'generating'::character varying, 'completed'::character varying, 'failed'::character varying, 'validation_error'::character varying]::text[])) OR role::text <> 'assistant'::text AND status IS NULL", name: "check_status_only_for_assistant"
  end

  create_table "app_collaborators", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "app_id", null: false
    t.bigint "membership_id", null: false
    t.string "role", default: "viewer"
    t.string "github_username"
    t.boolean "permissions_synced", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_collaborators_on_app_id"
    t.index ["membership_id"], name: "index_app_collaborators_on_membership_id"
    t.index ["team_id"], name: "index_app_collaborators_on_team_id"
  end

  create_table "app_domains", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "domain"
    t.string "status"
    t.datetime "verified_at"
    t.string "ssl_status"
    t.string "cloudflare_zone_id"
    t.string "cloudflare_record_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_domains_on_app_id"
  end

  create_table "app_files", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "app_id", null: false
    t.string "path", null: false
    t.text "content", null: false
    t.string "file_type"
    t.integer "size_bytes"
    t.string "checksum"
    t.boolean "is_entry_point", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "path"], name: "index_app_files_on_app_id_and_path", unique: true
    t.index ["app_id"], name: "index_app_files_on_app_id"
    t.index ["team_id"], name: "index_app_files_on_team_id"
  end

  create_table "app_generations", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "app_id", null: false
    t.text "prompt", null: false
    t.text "enhanced_prompt"
    t.string "status", default: "processing"
    t.string "ai_model", default: "kimi-k2"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.integer "duration_seconds"
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "total_cost"
    t.text "error_message"
    t.integer "retry_count", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_generations_on_app_id"
    t.index ["team_id"], name: "index_app_generations_on_team_id"
  end

  create_table "app_o_auth_providers", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "provider"
    t.string "client_id"
    t.string "client_secret"
    t.string "domain"
    t.string "redirect_uri"
    t.text "scopes"
    t.boolean "enabled"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_o_auth_providers_on_app_id"
  end

  create_table "app_security_policies", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "policy_name"
    t.string "policy_type"
    t.boolean "enabled", default: false
    t.text "configuration"
    t.text "description"
    t.datetime "last_violation"
    t.integer "violation_count"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_security_policies_on_app_id"
  end

  create_table "app_settings", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "key"
    t.text "value"
    t.boolean "encrypted"
    t.text "description"
    t.string "setting_type"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_settings_on_app_id"
  end

  create_table "app_table_columns", force: :cascade do |t|
    t.bigint "app_table_id", null: false
    t.string "name"
    t.string "column_type"
    t.text "options"
    t.boolean "required"
    t.string "default_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_table_id"], name: "index_app_table_columns_on_app_table_id"
  end

  create_table "app_tables", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_app_tables_on_app_id"
  end

  create_table "app_version_files", force: :cascade do |t|
    t.bigint "app_version_id", null: false
    t.bigint "app_file_id", null: false
    t.text "content"
    t.string "action"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_file_id"], name: "index_app_version_files_on_app_file_id"
    t.index ["app_version_id", "app_file_id"], name: "index_app_version_files_on_app_version_id_and_app_file_id", unique: true
    t.index ["app_version_id"], name: "index_app_version_files_on_app_version_id"
  end

  create_table "app_versions", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "app_id", null: false
    t.bigint "user_id"
    t.string "commit_sha"
    t.string "commit_message"
    t.string "version_number", null: false
    t.text "changelog"
    t.text "files_snapshot"
    t.text "changed_files"
    t.boolean "external_commit", default: false
    t.boolean "deployed", default: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "environment"
    t.boolean "bookmarked", default: false, null: false
    t.string "display_name"
    t.index ["app_id"], name: "index_app_versions_on_app_id"
    t.index ["bookmarked"], name: "index_app_versions_on_bookmarked"
    t.index ["team_id"], name: "index_app_versions_on_team_id"
    t.index ["user_id"], name: "index_app_versions_on_user_id"
  end

  create_table "apps", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.bigint "creator_id", null: false
    t.text "prompt", null: false
    t.string "app_type", default: "tool"
    t.string "framework", default: "react"
    t.string "status", default: "generating"
    t.string "visibility", default: "private"
    t.integer "base_price", default: 0, null: false
    t.string "stripe_product_id"
    t.string "preview_url"
    t.string "production_url"
    t.string "github_repo"
    t.integer "total_users", default: 0
    t.integer "total_revenue", default: 0
    t.integer "rating", default: 0
    t.boolean "featured", default: false
    t.datetime "featured_until"
    t.datetime "launch_date"
    t.string "ai_model"
    t.integer "ai_cost", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "deployment_url"
    t.string "deployment_status"
    t.datetime "deployed_at"
    t.string "staging_url"
    t.datetime "staging_deployed_at"
    t.datetime "preview_updated_at"
    t.text "logo_prompt"
    t.datetime "logo_generated_at"
    t.boolean "use_custom_database", default: false, null: false
    t.index ["creator_id"], name: "index_apps_on_creator_id"
    t.index ["featured"], name: "index_apps_on_featured"
    t.index ["slug"], name: "index_apps_on_slug", unique: true
    t.index ["status"], name: "index_apps_on_status"
    t.index ["team_id"], name: "index_apps_on_team_id"
    t.index ["use_custom_database"], name: "index_apps_on_use_custom_database"
    t.index ["visibility"], name: "index_apps_on_visibility"
  end

  create_table "build_logs", force: :cascade do |t|
    t.bigint "deployment_log_id", null: false
    t.string "level"
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["deployment_log_id"], name: "index_build_logs_on_deployment_log_id"
  end

  create_table "creator_profiles", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "membership_id", null: false
    t.string "username", null: false
    t.text "bio"
    t.integer "level", default: 1, null: false
    t.integer "total_earnings", default: 0
    t.integer "total_sales", default: 0
    t.string "verification_status", default: "unverified"
    t.datetime "featured_until"
    t.string "slug", null: false
    t.string "stripe_account_id"
    t.string "public_email"
    t.string "website_url"
    t.string "twitter_handle"
    t.string "github_username"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["membership_id"], name: "index_creator_profiles_on_membership_id"
    t.index ["slug"], name: "index_creator_profiles_on_slug", unique: true
    t.index ["team_id"], name: "index_creator_profiles_on_team_id"
    t.index ["username"], name: "index_creator_profiles_on_username", unique: true
  end

  create_table "deployment_logs", force: :cascade do |t|
    t.bigint "app_id", null: false
    t.string "environment"
    t.string "status"
    t.bigint "initiated_by_id", null: false
    t.string "deployment_url"
    t.text "error_message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "rollback_from_id"
    t.string "deployed_version"
    t.text "build_output"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id"], name: "index_deployment_logs_on_app_id"
    t.index ["initiated_by_id"], name: "index_deployment_logs_on_initiated_by_id"
    t.index ["rollback_from_id"], name: "index_deployment_logs_on_rollback_from_id"
  end

  create_table "feature_flags", force: :cascade do |t|
    t.string "name"
    t.boolean "enabled"
    t.integer "percentage"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "follows", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "follower_id", null: false
    t.bigint "followed_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_follows_on_followed_id"
    t.index ["follower_id", "followed_id"], name: "index_follows_on_follower_id_and_followed_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.index ["team_id"], name: "index_follows_on_team_id"
  end

  create_table "integrations_stripe_installations", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.bigint "oauth_stripe_account_id", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["oauth_stripe_account_id"], name: "index_stripe_installations_on_stripe_account_id"
    t.index ["team_id"], name: "index_integrations_stripe_installations_on_team_id"
  end

  create_table "invitations", id: :serial, force: :cascade do |t|
    t.string "email"
    t.string "uuid"
    t.integer "from_membership_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "team_id"
    t.bigint "invitation_list_id"
    t.index ["invitation_list_id"], name: "index_invitations_on_invitation_list_id"
    t.index ["team_id"], name: "index_invitations_on_team_id"
  end

  create_table "memberships", id: :serial, force: :cascade do |t|
    t.integer "user_id"
    t.integer "team_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "invitation_id"
    t.string "user_first_name"
    t.string "user_last_name"
    t.string "user_profile_photo_id"
    t.string "user_email"
    t.bigint "added_by_id"
    t.bigint "platform_agent_of_id"
    t.jsonb "role_ids", default: []
    t.boolean "platform_agent", default: false
    t.index ["added_by_id"], name: "index_memberships_on_added_by_id"
    t.index ["invitation_id"], name: "index_memberships_on_invitation_id"
    t.index ["platform_agent_of_id"], name: "index_memberships_on_platform_agent_of_id"
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "resource_owner_id", null: false
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.datetime "created_at", precision: nil, null: false
    t.datetime "revoked_at", precision: nil
    t.string "scopes", default: "", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "resource_owner_id"
    t.bigint "application_id", null: false
    t.string "token", null: false
    t.string "refresh_token"
    t.integer "expires_in"
    t.datetime "revoked_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.string "scopes"
    t.string "previous_refresh_token", default: "", null: false
    t.string "description"
    t.datetime "last_used_at"
    t.boolean "provisioned", default: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.string "name", null: false
    t.string "uid", null: false
    t.string "secret", null: false
    t.text "redirect_uri"
    t.string "scopes", default: "", null: false
    t.boolean "confidential", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "team_id"
    t.index ["team_id"], name: "index_oauth_applications_on_team_id"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "oauth_stripe_accounts", force: :cascade do |t|
    t.string "uid"
    t.jsonb "data"
    t.bigint "user_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["uid"], name: "index_oauth_stripe_accounts_on_uid", unique: true
    t.index ["user_id"], name: "index_oauth_stripe_accounts_on_user_id"
  end

  create_table "scaffolding_absolutely_abstract_creative_concepts", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["team_id"], name: "index_absolutely_abstract_creative_concepts_on_team_id"
  end

  create_table "scaffolding_completely_concrete_tangible_things", force: :cascade do |t|
    t.bigint "absolutely_abstract_creative_concept_id", null: false
    t.string "text_field_value"
    t.string "button_value"
    t.string "cloudinary_image_value"
    t.date "date_field_value"
    t.string "email_field_value"
    t.string "password_field_value"
    t.string "phone_field_value"
    t.string "super_select_value"
    t.text "text_area_value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "sort_order"
    t.datetime "date_and_time_field_value", precision: nil
    t.jsonb "multiple_button_values", default: []
    t.jsonb "multiple_super_select_values", default: []
    t.string "color_picker_value"
    t.boolean "boolean_button_value"
    t.string "option_value"
    t.jsonb "multiple_option_values", default: []
    t.boolean "boolean_checkbox_value"
    t.index ["absolutely_abstract_creative_concept_id"], name: "index_tangible_things_on_creative_concept_id"
  end

  create_table "scaffolding_completely_concrete_tangible_things_assignments", force: :cascade do |t|
    t.bigint "tangible_thing_id"
    t.bigint "membership_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["membership_id"], name: "index_tangible_things_assignments_on_membership_id"
    t.index ["tangible_thing_id"], name: "index_tangible_things_assignments_on_tangible_thing_id"
  end

  create_table "team_database_configs", force: :cascade do |t|
    t.bigint "team_id", null: false
    t.string "database_mode", default: "managed", null: false
    t.string "supabase_url"
    t.text "supabase_service_key"
    t.text "supabase_anon_key"
    t.string "migration_status"
    t.datetime "last_migration_at"
    t.json "export_format_preferences", default: {}
    t.text "custom_rls_policies"
    t.text "notes"
    t.boolean "validated", default: false
    t.datetime "last_validated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["database_mode"], name: "index_team_database_configs_on_database_mode"
    t.index ["team_id"], name: "index_team_database_configs_on_team_id"
  end

  create_table "teams", id: :serial, force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.boolean "being_destroyed"
    t.string "time_zone"
    t.string "locale"
  end

  create_table "users", id: :serial, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at", precision: nil
    t.datetime "remember_created_at", precision: nil
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at", precision: nil
    t.datetime "last_sign_in_at", precision: nil
    t.inet "current_sign_in_ip"
    t.inet "last_sign_in_ip"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.integer "current_team_id"
    t.string "first_name"
    t.string "last_name"
    t.string "time_zone"
    t.datetime "last_seen_at", precision: nil
    t.string "profile_photo_id"
    t.jsonb "ability_cache"
    t.datetime "last_notification_email_sent_at", precision: nil
    t.boolean "former_user", default: false, null: false
    t.string "encrypted_otp_secret"
    t.string "encrypted_otp_secret_iv"
    t.string "encrypted_otp_secret_salt"
    t.integer "consumed_timestep"
    t.boolean "otp_required_for_login"
    t.string "otp_backup_codes", array: true
    t.string "locale"
    t.bigint "platform_agent_of_id"
    t.string "otp_secret"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.string "supabase_user_id"
    t.string "supabase_sync_status", default: "pending"
    t.datetime "supabase_last_synced_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["platform_agent_of_id"], name: "index_users_on_platform_agent_of_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["supabase_sync_status"], name: "index_users_on_supabase_sync_status"
    t.index ["supabase_user_id"], name: "index_users_on_supabase_user_id", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
  end

  create_table "webhooks_incoming_bullet_train_webhooks", force: :cascade do |t|
    t.jsonb "data"
    t.datetime "processed_at", precision: nil
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "verified_at", precision: nil
  end

  create_table "webhooks_incoming_oauth_stripe_account_webhooks", force: :cascade do |t|
    t.jsonb "data"
    t.datetime "processed_at", precision: nil
    t.datetime "verified_at", precision: nil
    t.bigint "oauth_stripe_account_id"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.index ["oauth_stripe_account_id"], name: "index_stripe_webhooks_on_stripe_account_id"
  end

  create_table "webhooks_outgoing_deliveries", force: :cascade do |t|
    t.integer "endpoint_id"
    t.integer "event_id"
    t.text "endpoint_url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.datetime "delivered_at", precision: nil
    t.index ["endpoint_id", "event_id"], name: "index_webhooks_outgoing_deliveries_on_endpoint_id_and_event_id"
  end

  create_table "webhooks_outgoing_delivery_attempts", force: :cascade do |t|
    t.integer "delivery_id"
    t.integer "response_code"
    t.text "response_body"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.text "response_message"
    t.text "error_message"
    t.integer "attempt_number"
    t.index ["delivery_id"], name: "index_webhooks_outgoing_delivery_attempts_on_delivery_id"
  end

  create_table "webhooks_outgoing_endpoints", force: :cascade do |t|
    t.bigint "team_id"
    t.text "url"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.string "name"
    t.jsonb "event_type_ids", default: []
    t.bigint "scaffolding_absolutely_abstract_creative_concept_id"
    t.integer "api_version", null: false
    t.string "webhook_secret", null: false
    t.datetime "deactivation_limit_reached_at"
    t.datetime "deactivated_at"
    t.integer "consecutive_failed_deliveries", default: 0, null: false
    t.index ["scaffolding_absolutely_abstract_creative_concept_id"], name: "index_endpoints_on_abstract_creative_concept_id"
    t.index ["team_id", "deactivated_at"], name: "idx_on_team_id_deactivated_at_d8a33babf2"
    t.index ["team_id"], name: "index_webhooks_outgoing_endpoints_on_team_id"
  end

  create_table "webhooks_outgoing_events", force: :cascade do |t|
    t.integer "subject_id"
    t.string "subject_type"
    t.jsonb "data"
    t.datetime "created_at", precision: nil, null: false
    t.datetime "updated_at", precision: nil, null: false
    t.bigint "team_id"
    t.string "uuid"
    t.jsonb "payload"
    t.string "event_type_id"
    t.integer "api_version", null: false
    t.index ["team_id"], name: "index_webhooks_outgoing_events_on_team_id"
  end

  add_foreign_key "account_onboarding_invitation_lists", "teams"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "app_api_calls", "apps"
  add_foreign_key "app_api_integrations", "apps"
  add_foreign_key "app_chat_messages", "app_versions"
  add_foreign_key "app_chat_messages", "apps"
  add_foreign_key "app_chat_messages", "users"
  add_foreign_key "app_collaborators", "apps"
  add_foreign_key "app_collaborators", "memberships"
  add_foreign_key "app_collaborators", "teams"
  add_foreign_key "app_domains", "apps"
  add_foreign_key "app_files", "apps"
  add_foreign_key "app_files", "teams"
  add_foreign_key "app_generations", "apps"
  add_foreign_key "app_generations", "teams"
  add_foreign_key "app_o_auth_providers", "apps"
  add_foreign_key "app_security_policies", "apps"
  add_foreign_key "app_settings", "apps"
  add_foreign_key "app_table_columns", "app_tables"
  add_foreign_key "app_tables", "apps"
  add_foreign_key "app_version_files", "app_files"
  add_foreign_key "app_version_files", "app_versions"
  add_foreign_key "app_versions", "apps"
  add_foreign_key "app_versions", "teams"
  add_foreign_key "app_versions", "users"
  add_foreign_key "apps", "memberships", column: "creator_id"
  add_foreign_key "apps", "teams"
  add_foreign_key "build_logs", "deployment_logs"
  add_foreign_key "creator_profiles", "memberships"
  add_foreign_key "creator_profiles", "teams"
  add_foreign_key "deployment_logs", "apps"
  add_foreign_key "deployment_logs", "deployment_logs", column: "rollback_from_id"
  add_foreign_key "deployment_logs", "users", column: "initiated_by_id"
  add_foreign_key "follows", "creator_profiles", column: "followed_id"
  add_foreign_key "follows", "teams"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "integrations_stripe_installations", "oauth_stripe_accounts"
  add_foreign_key "integrations_stripe_installations", "teams"
  add_foreign_key "invitations", "account_onboarding_invitation_lists", column: "invitation_list_id"
  add_foreign_key "invitations", "teams"
  add_foreign_key "memberships", "invitations"
  add_foreign_key "memberships", "memberships", column: "added_by_id"
  add_foreign_key "memberships", "oauth_applications", column: "platform_agent_of_id"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_applications", "teams"
  add_foreign_key "oauth_stripe_accounts", "users"
  add_foreign_key "scaffolding_absolutely_abstract_creative_concepts", "teams"
  add_foreign_key "scaffolding_completely_concrete_tangible_things", "scaffolding_absolutely_abstract_creative_concepts", column: "absolutely_abstract_creative_concept_id"
  add_foreign_key "scaffolding_completely_concrete_tangible_things_assignments", "memberships"
  add_foreign_key "scaffolding_completely_concrete_tangible_things_assignments", "scaffolding_completely_concrete_tangible_things", column: "tangible_thing_id"
  add_foreign_key "team_database_configs", "teams"
  add_foreign_key "users", "oauth_applications", column: "platform_agent_of_id"
  add_foreign_key "webhooks_outgoing_endpoints", "scaffolding_absolutely_abstract_creative_concepts"
  add_foreign_key "webhooks_outgoing_endpoints", "teams"
  add_foreign_key "webhooks_outgoing_events", "teams"
end
