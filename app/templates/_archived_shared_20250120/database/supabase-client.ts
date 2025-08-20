import { createClient } from '@supabase/supabase-js';

const supabaseUrl = '{{SUPABASE_URL}}';
const supabaseAnonKey = '{{SUPABASE_ANON_KEY}}';

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase environment variables');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});

// Export types for TypeScript
export type { User, Session } from '@supabase/supabase-js';