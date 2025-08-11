import { useState, useEffect, useCallback } from 'react';
import { db } from '@/lib/app-scoped-db';

interface UseInfiniteQueryOptions {
  tableName: string;
  columns?: string;
  pageSize?: number;
  trailingQuery?: (query: any) => any;
  enabled?: boolean;
}

interface UseInfiniteQueryResult<T = any> {
  data: T[];
  count: number | null;
  isLoading: boolean;
  isFetching: boolean;
  hasMore: boolean;
  fetchNextPage: () => Promise<void>;
  error: Error | null;
  refetch: () => Promise<void>;
}

/**
 * React hook for infinite lists, fetching data from Supabase with app-scoped tables
 * 
 * @param options Configuration options for the query
 * @returns Query state and functions for infinite loading
 */
export function useInfiniteQuery<T = any>(
  options: UseInfiniteQueryOptions
): UseInfiniteQueryResult<T> {
  const {
    tableName,
    columns = '*',
    pageSize = 20,
    trailingQuery,
    enabled = true
  } = options;

  const [data, setData] = useState<T[]>([]);
  const [count, setCount] = useState<number | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isFetching, setIsFetching] = useState(false);
  const [hasMore, setHasMore] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [currentPage, setCurrentPage] = useState(0);

  // Get total count
  const fetchCount = useCallback(async () => {
    try {
      let query = db.from(tableName).select('*', { count: 'exact', head: true });
      
      if (trailingQuery) {
        query = trailingQuery(query);
      }
      
      const { count: totalCount, error: countError } = await query;
      
      if (countError) {
        console.error('Error fetching count:', countError);
        return;
      }
      
      setCount(totalCount);
    } catch (err) {
      console.error('Count fetch error:', err);
    }
  }, [tableName, trailingQuery]);

  // Fetch a page of data
  const fetchPage = useCallback(async (page: number, append = false) => {
    if (!enabled) return;
    
    setError(null);
    
    if (page === 0) {
      setIsLoading(true);
    } else {
      setIsFetching(true);
    }

    try {
      const from = page * pageSize;
      const to = from + pageSize - 1;
      
      let query = db.from(tableName)
        .select(columns)
        .range(from, to);
      
      if (trailingQuery) {
        query = trailingQuery(query);
      }
      
      const { data: pageData, error: fetchError } = await query;
      
      if (fetchError) {
        throw new Error(fetchError.message);
      }
      
      const newData = pageData || [];
      
      if (append) {
        setData(prev => [...prev, ...newData]);
      } else {
        setData(newData);
      }
      
      // Check if there's more data
      setHasMore(newData.length === pageSize);
      
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Unknown error';
      console.error('Fetch error:', errorMessage);
      setError(new Error(errorMessage));
    } finally {
      setIsLoading(false);
      setIsFetching(false);
    }
  }, [tableName, columns, pageSize, trailingQuery, enabled]);

  // Fetch next page
  const fetchNextPage = useCallback(async () => {
    if (isFetching || !hasMore) return;
    
    const nextPage = currentPage + 1;
    setCurrentPage(nextPage);
    await fetchPage(nextPage, true);
  }, [currentPage, fetchPage, isFetching, hasMore]);

  // Refetch all data
  const refetch = useCallback(async () => {
    setCurrentPage(0);
    await fetchPage(0, false);
    await fetchCount();
  }, [fetchPage, fetchCount]);

  // Initial load
  useEffect(() => {
    if (enabled) {
      setCurrentPage(0);
      fetchPage(0, false);
      fetchCount();
    }
  }, [tableName, columns, pageSize, enabled, fetchPage, fetchCount]);

  return {
    data,
    count,
    isLoading,
    isFetching,
    hasMore,
    fetchNextPage,
    error,
    refetch
  };
}