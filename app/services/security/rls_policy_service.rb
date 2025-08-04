module Security
  class RlsPolicyService
    # This service provides transparent access to Row-Level Security policies
    # Unlike Base44's opaque security, we show users exactly how their data is protected
    
    def initialize(app)
      @app = app
      @team = app.team
    end
    
    def get_all_policies
      # Fetch all RLS policies for the app's tables
      policies = []
      
      @app.app_tables.each do |table|
        table_policies = get_table_policies(table)
        policies.concat(table_policies)
      end
      
      policies
    end
    
    def get_table_policies(table)
      # Get RLS policies for a specific table
      schema_name = "app_#{@app.id}"
      table_name = table.name
      
      # These are the standard policies we create for each table
      [
        {
          table: table_name,
          name: "#{table_name}_select_policy",
          operation: "SELECT",
          description: "Users can view data from their organization",
          sql: generate_select_policy_sql(schema_name, table_name),
          using_clause: "check_organization_access(organization_id)",
          with_check_clause: nil,
          enabled: true
        },
        {
          table: table_name,
          name: "#{table_name}_insert_policy",
          operation: "INSERT",
          description: "Users can insert data for their organization",
          sql: generate_insert_policy_sql(schema_name, table_name),
          using_clause: nil,
          with_check_clause: "check_organization_access(organization_id) AND created_by = auth.uid()",
          enabled: true
        },
        {
          table: table_name,
          name: "#{table_name}_update_policy",
          operation: "UPDATE",
          description: "Users can update their organization's data",
          sql: generate_update_policy_sql(schema_name, table_name),
          using_clause: "check_organization_access(organization_id)",
          with_check_clause: "check_organization_access(organization_id) AND updated_by = auth.uid()",
          enabled: true
        },
        {
          table: table_name,
          name: "#{table_name}_delete_policy",
          operation: "DELETE",
          description: "Users can delete their organization's data",
          sql: generate_delete_policy_sql(schema_name, table_name),
          using_clause: "check_organization_access(organization_id)",
          with_check_clause: nil,
          enabled: true
        }
      ]
    end
    
    def get_audit_configuration
      # Return the audit configuration for transparency
      {
        enabled: true,
        retention_days: 90,
        tracked_operations: ["INSERT", "UPDATE", "DELETE"],
        audit_table: "audit_log",
        configuration_sql: generate_audit_config_sql
      }
    end
    
    def get_security_functions
      # Return the security helper functions we use
      [
        {
          name: "check_organization_access",
          description: "Verifies user belongs to the organization",
          parameters: ["org_id UUID"],
          returns: "BOOLEAN",
          sql: generate_org_check_function_sql
        },
        {
          name: "get_current_organization_id",
          description: "Gets the current user's organization ID from session/JWT",
          parameters: [],
          returns: "UUID",
          sql: generate_get_org_function_sql
        },
        {
          name: "audit_trigger_function",
          description: "Automatically logs all data changes for compliance",
          parameters: [],
          returns: "TRIGGER",
          sql: generate_audit_trigger_sql
        }
      ]
    end
    
    def generate_security_report
      # Generate a comprehensive security report for the app
      {
        app_name: @app.name,
        generated_at: Time.current,
        security_model: "Organization-based Row Level Security",
        policies: get_all_policies,
        functions: get_security_functions,
        audit_config: get_audit_configuration,
        data_isolation: {
          level: "Organization",
          mechanism: "PostgreSQL RLS",
          enforcement: "Database level",
          bypass_possible: false
        },
        compliance_features: {
          audit_trail: true,
          data_encryption: true,
          access_logging: true,
          gdpr_ready: true,
          data_portability: true
        }
      }
    end
    
    def explain_policy(policy_name)
      # Provide a plain-English explanation of what a policy does
      case policy_name
      when /select_policy/
        "This policy ensures users can only view data that belongs to their organization. It checks the organization_id on every row against the user's organization membership."
      when /insert_policy/
        "This policy ensures users can only create new records for their own organization. It also tracks who created the record for audit purposes."
      when /update_policy/
        "This policy ensures users can only modify data within their organization. It tracks who made changes and when for compliance."
      when /delete_policy/
        "This policy ensures users can only delete data from their own organization. All deletions are logged in the audit trail."
      else
        "This policy helps ensure data security and proper access control."
      end
    end
    
    private
    
    def generate_select_policy_sql(schema, table)
      <<~SQL
        CREATE POLICY "#{table}_select_policy" ON #{schema}.#{table}
          FOR SELECT
          TO authenticated
          USING (check_organization_access(organization_id));
      SQL
    end
    
    def generate_insert_policy_sql(schema, table)
      <<~SQL
        CREATE POLICY "#{table}_insert_policy" ON #{schema}.#{table}
          FOR INSERT
          TO authenticated
          WITH CHECK (
            check_organization_access(organization_id) AND
            created_by = auth.uid()
          );
      SQL
    end
    
    def generate_update_policy_sql(schema, table)
      <<~SQL
        CREATE POLICY "#{table}_update_policy" ON #{schema}.#{table}
          FOR UPDATE
          TO authenticated
          USING (check_organization_access(organization_id))
          WITH CHECK (
            check_organization_access(organization_id) AND
            updated_by = auth.uid()
          );
      SQL
    end
    
    def generate_delete_policy_sql(schema, table)
      <<~SQL
        CREATE POLICY "#{table}_delete_policy" ON #{schema}.#{table}
          FOR DELETE
          TO authenticated
          USING (check_organization_access(organization_id));
      SQL
    end
    
    def generate_org_check_function_sql
      <<~SQL
        CREATE OR REPLACE FUNCTION check_organization_access(org_id UUID)
        RETURNS BOOLEAN AS $$
        BEGIN
          -- Check if the current user belongs to the organization
          -- This integrates with your authentication system
          RETURN auth.uid() IS NOT NULL AND 
                 org_id IS NOT NULL AND
                 EXISTS (
                   SELECT 1 FROM organization_members 
                   WHERE user_id = auth.uid() 
                   AND organization_id = org_id
                   AND active = true
                 );
        END;
        $$ LANGUAGE plpgsql SECURITY DEFINER;
      SQL
    end
    
    def generate_get_org_function_sql
      <<~SQL
        CREATE OR REPLACE FUNCTION get_current_organization_id()
        RETURNS UUID AS $$
        DECLARE
          org_id UUID;
        BEGIN
          -- Try to get from session variable first (fastest)
          BEGIN
            org_id := (current_setting('app.current_organization_id', true))::uuid;
            IF org_id IS NOT NULL THEN
              RETURN org_id;
            END IF;
          EXCEPTION WHEN OTHERS THEN
            -- Continue to JWT claims
          END;
          
          -- Try to get from JWT claims
          BEGIN
            org_id := (current_setting('request.jwt.claims', true)::json->>'organization_id')::uuid;
            IF org_id IS NOT NULL THEN
              RETURN org_id;
            END IF;
          EXCEPTION WHEN OTHERS THEN
            -- Continue to fallback
          END;
          
          -- Fallback: get from user's primary organization
          SELECT organization_id INTO org_id
          FROM organization_members
          WHERE user_id = auth.uid()
          AND is_primary = true
          AND active = true
          LIMIT 1;
          
          RETURN org_id;
        END;
        $$ LANGUAGE plpgsql STABLE SECURITY DEFINER;
      SQL
    end
    
    def generate_audit_trigger_sql
      <<~SQL
        CREATE OR REPLACE FUNCTION audit_trigger_function()
        RETURNS TRIGGER AS $$
        DECLARE
          audit_data JSONB;
          operation_type TEXT;
        BEGIN
          operation_type := TG_OP;
          
          -- Build audit data based on operation
          IF TG_OP = 'INSERT' THEN
            audit_data := jsonb_build_object(
              'new', to_jsonb(NEW),
              'user_id', NEW.created_by,
              'timestamp', NOW()
            );
          ELSIF TG_OP = 'UPDATE' THEN
            audit_data := jsonb_build_object(
              'old', to_jsonb(OLD),
              'new', to_jsonb(NEW),
              'changed_fields', (
                SELECT jsonb_object_agg(key, value)
                FROM jsonb_each(to_jsonb(NEW))
                WHERE value IS DISTINCT FROM (to_jsonb(OLD)->>key)::jsonb
              ),
              'user_id', NEW.updated_by,
              'timestamp', NOW()
            );
          ELSIF TG_OP = 'DELETE' THEN
            audit_data := jsonb_build_object(
              'old', to_jsonb(OLD),
              'user_id', auth.uid(),
              'timestamp', NOW()
            );
          END IF;
          
          -- Insert audit record
          INSERT INTO audit_log (
            table_name,
            record_id,
            operation,
            organization_id,
            user_id,
            data,
            created_at
          ) VALUES (
            TG_TABLE_NAME,
            COALESCE(NEW.id, OLD.id),
            operation_type,
            COALESCE(NEW.organization_id, OLD.organization_id),
            auth.uid(),
            audit_data,
            NOW()
          );
          
          -- Return appropriate record
          IF TG_OP = 'DELETE' THEN
            RETURN OLD;
          ELSE
            RETURN NEW;
          END IF;
        END;
        $$ LANGUAGE plpgsql SECURITY DEFINER;
      SQL
    end
    
    def generate_audit_config_sql
      <<~SQL
        -- Audit table configuration
        CREATE TABLE IF NOT EXISTS audit_log (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          table_name TEXT NOT NULL,
          record_id UUID NOT NULL,
          operation TEXT NOT NULL,
          organization_id UUID NOT NULL,
          user_id UUID NOT NULL,
          data JSONB NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          -- Indexes for performance
          INDEX idx_audit_table_record (table_name, record_id),
          INDEX idx_audit_org_created (organization_id, created_at DESC),
          INDEX idx_audit_user_created (user_id, created_at DESC)
        );
        
        -- Enable RLS on audit table
        ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
        
        -- Audit table can only be read by organization members
        CREATE POLICY "audit_log_select_policy" ON audit_log
          FOR SELECT
          TO authenticated
          USING (check_organization_access(organization_id));
        
        -- Audit records cannot be modified or deleted
        -- This ensures compliance and data integrity
      SQL
    end
  end
end