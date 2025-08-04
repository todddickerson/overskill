class Supabase::OrganizationContextService
  # Service to manage organization context and user roles for RLS
  # This connects OverSkill's main database with Supabase for seamless multi-tenancy
  
  def self.get_organization_for_user(user_id)
    # Get the user's current organization context
    user = User.find_by(id: user_id)
    return nil unless user
    
    # Get the user's primary team (organization)
    # Note: In OverSkill, team_id = organization_id (teams represent organizations)
    membership = user.memberships.includes(:team).first
    return nil unless membership
    
    # BulletTrain uses role_ids JSONB array, we'll determine the primary role
    primary_role = get_primary_role_from_membership(membership)
    
    {
      organization_id: membership.team.id,  # team_id = organization_id
      organization_name: membership.team.name,
      user_role: primary_role,
      permissions: get_role_permissions(primary_role)
    }
  end
  
  def self.get_user_role_in_organization(user_id, organization_id)
    # Get specific role for user in organization
    # Note: organization_id = team_id in OverSkill's architecture
    membership = Membership.find_by(
      user_id: user_id,
      team_id: organization_id  # team_id = organization_id
    )
    
    return nil unless membership
    
    # BulletTrain uses role_ids JSONB array
    primary_role = get_primary_role_from_membership(membership)
    
    {
      role: primary_role,
      permissions: get_role_permissions(primary_role),
      is_admin: primary_role == 'admin',  # BulletTrain admin role
      can_manage_data: primary_role.in?(['admin', 'editor', 'default'])
    }
  end
  
  def self.user_belongs_to_organization?(user_id, organization_id)
    # Verify user belongs to organization
    # Note: organization_id = team_id in OverSkill
    Membership.exists?(
      user_id: user_id,
      team_id: organization_id  # team_id = organization_id
    )
  end
  
  # BulletTrain Role System Helper
  # BulletTrain uses role_ids JSONB array for flexible role assignment
  # Each membership can have multiple roles stored in role_ids
  def self.get_primary_role_from_membership(membership)
    return 'default' unless membership
    
    # Check role_ids array - BulletTrain pattern
    if membership.role_ids.present? && membership.role_ids.any?
      # Priority: admin > editor > default
      return 'admin' if membership.role_ids.include?('admin')
      return 'editor' if membership.role_ids.include?('editor')
      return membership.role_ids.first
    end
    
    # Fallback to default role
    'default'
  end
  
  def self.get_all_roles_from_membership(membership)
    return ['default'] unless membership
    
    # Return all roles or default
    membership.role_ids.presence || ['default']
  end
  
  def self.get_organization_apps(organization_id)
    # Get all apps for an organization
    team = Team.find_by(id: organization_id)
    return [] unless team
    
    team.apps.select(:id, :name, :status).map do |app|
      {
        app_id: app.id,
        app_name: app.name,
        status: app.status
      }
    end
  end
  
  def self.create_jwt_claims(user_id, organization_id = nil)
    # Create JWT claims for Supabase authentication
    user = User.find_by(id: user_id)
    return nil unless user
    
    organization_id ||= get_organization_for_user(user_id)&.dig(:organization_id)
    return nil unless organization_id
    
    role_info = get_user_role_in_organization(user_id, organization_id)
    
    {
      sub: user_id.to_s,
      email: user.email,
      organization_id: organization_id.to_s,
      organization_role: role_info&.dig(:role) || 'member',
      permissions: role_info&.dig(:permissions) || [],
      iss: 'overskill',
      aud: 'authenticated',
      exp: 24.hours.from_now.to_i,
      iat: Time.current.to_i
    }
  end
  
  def self.set_supabase_context(user_id, organization_id, app_id)
    # Set context variables for Supabase RLS
    # This would be called before making Supabase requests
    
    role_info = get_user_role_in_organization(user_id, organization_id)
    
    {
      'app.current_organization_id' => organization_id.to_s,
      'app.current_user_id' => user_id.to_s,
      'app.current_app_id' => app_id.to_s,
      'app.user_role' => role_info&.dig(:role) || 'member',
      'app.operation_type' => 'normal_operation',
      'app.request_id' => SecureRandom.uuid
    }
  end
  
  private
  
  def self.get_role_permissions(role)
    # Define permissions for each role based on BulletTrain's roles.yml
    # BulletTrain roles: admin (includes editor), editor, default
    case role.to_s
    when 'admin'
      # Admin has manage permissions on all models per roles.yml
      %w[
        read_data write_data delete_data
        manage_schema manage_users export_data
        view_audit_logs manage_app_settings
        manage_team manage_apps manage_collaborators
      ]
    when 'editor'
      # Editor has specific manage permissions per roles.yml
      %w[
        read_data write_data delete_data
        manage_own_data view_own_audit_logs
        create_apps edit_apps
      ]
    when 'default'
      # Default role has basic read/manage permissions per roles.yml
      %w[
        read_data write_data
        manage_own_apps view_own_data
        create_invitations
      ]
    else
      # Minimal permissions for unknown roles
      %w[read_data]
    end
  end
end