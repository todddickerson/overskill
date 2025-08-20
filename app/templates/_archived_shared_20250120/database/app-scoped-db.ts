import { SupabaseClient } from '@supabase/supabase-js';
import { supabase } from './supabase-client';

/**
 * App-Scoped Database Wrapper
 * 
 * This wrapper ensures all database operations are automatically scoped to this app
 * Tables are prefixed with app_{{APP_ID}}_ for multi-tenant isolation
 * 
 * Usage:
 *   const db = new AppScopedDatabase();
 *   const todos = await db.from('todos').select('*');
 *   // Actually queries: app_{{APP_ID}}_todos
 */
export class AppScopedDatabase {
  private appId: string;
  private supabase: SupabaseClient;
  
  constructor(supabaseClient: SupabaseClient = supabase) {
    this.supabase = supabaseClient;
    this.appId = '{{APP_ID}}';
    
    // Development logging - remove in production
    if (process.env.NODE_ENV === 'development') {
      console.log(`🗃️ [${this.appId}] App-scoped database initialized`);
    }
  }
  
  /**
   * Query a table with automatic app scoping
   * @param table - The logical table name (e.g., 'todos')
   * @returns Supabase query builder for the scoped table
   */
  from(table: string) {
    const scopedTable = `app_${this.appId}_${table}`;
    
    // Development logging for debugging
    if (process.env.NODE_ENV === 'development') {
      console.log(`🗃️ [${this.appId}] Querying table: ${scopedTable}`);
    }
    
    return this.supabase.from(scopedTable);
  }
  
  /**
   * Get the actual scoped table name
   * @param table - The logical table name
   * @returns The scoped table name (app_{{APP_ID}}_tablename)
   */
  getTableName(table: string): string {
    return `app_${this.appId}_${table}`;
  }
  
  /**
   * Get the app ID this database is scoped to
   */
  getAppId(): string {
    return this.appId;
  }
  
  /**
   * Direct access to Supabase client for auth and other operations
   * Note: This bypasses app scoping - use carefully
   */
  get client(): SupabaseClient {
    return this.supabase;
  }
  
  /**
   * Execute raw SQL with app scoping context
   * Use this for complex queries that need manual scoping
   */
  async rpc(fn: string, args?: Record<string, any>) {
    // Add app_id to the function arguments for server-side filtering
    const scopedArgs = {
      ...args,
      app_id: this.appId
    };
    
    if (process.env.NODE_ENV === 'development') {
      console.log(`🗃️ [${this.appId}] Calling RPC: ${fn}`, scopedArgs);
    }
    
    return this.supabase.rpc(fn, scopedArgs);
  }
}

// Export singleton instance for convenience
export const db = new AppScopedDatabase();

// Export the class for custom instances
export default AppScopedDatabase;