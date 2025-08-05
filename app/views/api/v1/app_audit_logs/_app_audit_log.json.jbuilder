json.extract! app_audit_log,
  :id,
  :app_id,
  :action_type,
  :performed_by,
  :target_resource,
  :resource_id,
  :change_details,
  :ip_address,
  :user_agent,
  :occurred_at,
  # 🚅 super scaffolding will insert new fields above this line.
  :created_at,
  :updated_at

# 🚅 super scaffolding will insert file-related logic above this line.
