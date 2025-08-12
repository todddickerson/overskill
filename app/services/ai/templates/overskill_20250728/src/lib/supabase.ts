import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// CRITICAL: Set RLS context before any database operation
export const setRLSContext = async (userId: string) => {
  const { error } = await supabase.rpc('set_config', {
    setting_name: 'app.current_user_id',
    new_value: userId,
    is_local: true
  });
  if (error) throw error;
};

// Initialize RLS on app load
export const initializeApp = async () => {
  const ownerId = import.meta.env.VITE_OWNER_ID;
  if (ownerId) {
    await setRLSContext(ownerId);
  }
};

// Helper for authenticated operations
export const withRLS = async <T>(userId: string, operation: () => Promise<T>): Promise<T> => {
  await setRLSContext(userId);
  return operation();
};
