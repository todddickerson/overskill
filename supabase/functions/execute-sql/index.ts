// Supabase Edge Function to execute SQL commands
// Deploy with: supabase functions deploy execute-sql

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get the authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('Missing authorization header')
    }

    // Verify this is a service role key (has admin privileges)
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    
    // Only allow service role key
    if (!authHeader.includes(supabaseServiceKey)) {
      throw new Error('Unauthorized - service role key required')
    }

    // Parse the request body
    const { sql, params = [] } = await req.json()
    
    if (!sql) {
      throw new Error('SQL command is required')
    }

    // Security checks
    const sqlLower = sql.toLowerCase()
    
    // Only allow specific safe operations
    const allowedOperations = [
      'create table',
      'create index',
      'create policy',
      'alter table',
      'grant',
      'create or replace function',
      'create trigger'
    ]
    
    const isAllowed = allowedOperations.some(op => sqlLower.includes(op))
    
    // Block dangerous operations
    const blockedOperations = [
      'drop database',
      'drop schema public',
      'truncate auth.',
      'delete from auth.',
      'drop table auth.',
      'drop table storage.'
    ]
    
    const isBlocked = blockedOperations.some(op => sqlLower.includes(op))
    
    if (isBlocked || !isAllowed) {
      throw new Error('SQL operation not allowed')
    }

    // Additional validation: must include app_ prefix for table operations
    if (sqlLower.includes('create table') || sqlLower.includes('alter table')) {
      if (!sqlLower.includes('app_')) {
        throw new Error('Table names must include app_ prefix')
      }
    }

    // Create admin client
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      auth: {
        persistSession: false
      }
    })

    // Execute the SQL
    const { data, error } = await supabase.rpc('exec_dynamic_sql', {
      sql_query: sql,
      sql_params: params
    })

    if (error) {
      // If the RPC function doesn't exist, we need to create it first
      if (error.message.includes('function') && error.message.includes('does not exist')) {
        // Create the function
        const createFunctionSQL = `
          CREATE OR REPLACE FUNCTION exec_dynamic_sql(sql_query text, sql_params jsonb DEFAULT '[]'::jsonb)
          RETURNS jsonb
          LANGUAGE plpgsql
          SECURITY DEFINER
          SET search_path = public
          AS $$
          DECLARE
            result jsonb;
          BEGIN
            -- Security check: only allow from edge functions
            IF current_setting('request.jwt.claims', true)::jsonb->>'role' != 'service_role' THEN
              RAISE EXCEPTION 'Unauthorized';
            END IF;
            
            -- Execute the SQL
            EXECUTE sql_query;
            
            -- Return success
            RETURN jsonb_build_object('success', true, 'message', 'SQL executed successfully');
          EXCEPTION
            WHEN OTHERS THEN
              RETURN jsonb_build_object('success', false, 'error', SQLERRM);
          END;
          $$;
        `
        
        // Try to create the function (this might fail if we don't have permissions)
        return new Response(
          JSON.stringify({
            success: false,
            error: 'exec_dynamic_sql function needs to be created. Please run this SQL in Supabase Dashboard:\n\n' + createFunctionSQL
          }),
          { 
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            status: 500
          }
        )
      }
      
      throw error
    }

    return new Response(
      JSON.stringify({ success: true, data }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200
      }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400
      }
    )
  }
})