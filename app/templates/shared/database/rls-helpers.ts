/**
 * Row Level Security (RLS) Helper Functions
 * 
 * These functions help create and manage RLS policies for app-scoped tables
 * All tables use app_id column for isolation between different apps
 */

/**
 * Generate RLS policy SQL for a table
 * @param tableName - The full table name (e.g., app_123_todos)
 * @param appId - The app ID for isolation
 * @param policyName - Optional custom policy name
 * @returns SQL string to create the RLS policy
 */
export const createRLSPolicy = (tableName: string, appId: string, policyName?: string): string => {
  const policy = policyName || `app_${appId}_isolation`;
  
  return `
    -- Enable RLS on the table
    ALTER TABLE ${tableName} ENABLE ROW LEVEL SECURITY;
    
    -- Create policy for app isolation
    CREATE POLICY "${policy}" ON ${tableName}
      FOR ALL USING (app_id = '${appId}');
  `;
};

/**
 * Generate SQL to create an app-scoped table with standard columns
 * @param tableName - The logical table name (e.g., 'todos')
 * @param appId - The app ID
 * @param customColumns - Additional columns as SQL
 * @returns Complete CREATE TABLE SQL with RLS
 */
export const createAppScopedTable = (
  tableName: string,
  appId: string,
  customColumns: string = ''
): string => {
  const fullTableName = `app_${appId}_${tableName}`;
  
  return `
    -- Create app-scoped table
    CREATE TABLE ${fullTableName} (
      id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
      app_id text NOT NULL DEFAULT '${appId}',
      created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
      updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL
      ${customColumns ? ',' + customColumns : ''}
    );
    
    -- Enable RLS and create policy
    ALTER TABLE ${fullTableName} ENABLE ROW LEVEL SECURITY;
    
    CREATE POLICY "app_${appId}_isolation" ON ${fullTableName}
      FOR ALL USING (app_id = '${appId}');
    
    -- Create updated_at trigger
    CREATE OR REPLACE TRIGGER update_${fullTableName}_updated_at
      BEFORE UPDATE ON ${fullTableName}
      FOR EACH ROW
      EXECUTE FUNCTION update_updated_at_column();
  `;
};

/**
 * Generate SQL to drop an app-scoped table and its policies
 * @param tableName - The logical table name
 * @param appId - The app ID
 * @returns DROP TABLE SQL
 */
export const dropAppScopedTable = (tableName: string, appId: string): string => {
  const fullTableName = `app_${appId}_${tableName}`;
  
  return `
    -- Drop table (policies are dropped automatically)
    DROP TABLE IF EXISTS ${fullTableName};
  `;
};

/**
 * Validate that a table name is safe for app scoping
 * @param tableName - The table name to validate
 * @returns true if safe, false otherwise
 */
export const isValidTableName = (tableName: string): boolean => {
  // Only allow alphanumeric and underscores, must start with letter
  const regex = /^[a-zA-Z][a-zA-Z0-9_]*$/;
  return regex.test(tableName) && tableName.length <= 50;
};

/**
 * Get the full scoped table name
 * @param tableName - The logical table name
 * @param appId - The app ID
 * @returns The full scoped table name
 */
export const getScopedTableName = (tableName: string, appId: string): string => {
  return `app_${appId}_${tableName}`;
};

/**
 * Common table templates for typical app needs
 */
export const tableTemplates = {
  users: `
    email text UNIQUE NOT NULL,
    name text,
    avatar_url text,
    role text DEFAULT 'user'
  `,
  
  posts: `
    title text NOT NULL,
    content text,
    author_id uuid REFERENCES auth.users(id),
    published boolean DEFAULT false,
    slug text
  `,
  
  todos: `
    title text NOT NULL,
    description text,
    completed boolean DEFAULT false,
    user_id uuid REFERENCES auth.users(id),
    priority text DEFAULT 'medium'
  `,
  
  settings: `
    key text NOT NULL,
    value jsonb,
    user_id uuid REFERENCES auth.users(id),
    UNIQUE(key, user_id)
  `
};

/**
 * Create a table from a template
 * @param template - Template name from tableTemplates
 * @param tableName - The logical table name
 * @param appId - The app ID
 * @returns SQL to create the table
 */
export const createFromTemplate = (
  template: keyof typeof tableTemplates,
  tableName: string,
  appId: string
): string => {
  const columns = tableTemplates[template];
  return createAppScopedTable(tableName, appId, columns);
};