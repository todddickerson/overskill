// Supabase integration removed for simplified deployment
// This is a stub file to maintain compatibility with existing imports

export const supabase = null;

export const setRLSContext = async (userId: string) => {
  // No-op: Database integration disabled
  console.log('Database integration disabled');
};

export const initializeApp = async () => {
  // No-op: App initialization simplified
  console.log('App initialized (database disabled)');
};

export const withRLS = async <T>(userId: string, operation: () => Promise<T>): Promise<T> => {
  // No-op: Pass through operation without RLS
  return operation();
};
