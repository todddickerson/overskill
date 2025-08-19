// React Hook for R2 Asset Management
// Provides easy asset loading with error handling and preloading

import { useState, useEffect, useCallback } from 'react';
import assetResolver from './assetResolver';

/**
 * Hook for loading assets with automatic R2/local resolution
 * @param {string} assetPath - Path to asset (e.g., 'images/hero.jpg')
 * @param {object} options - Loading options
 * @returns {object} - { url, loading, error, reload }
 */
export const useAsset = (assetPath, options = {}) => {
  const {
    preload = false,
    fallback = null,
    onError = null,
    onLoad = null
  } = options;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [url, setUrl] = useState(null);

  const loadAsset = useCallback(async () => {
    if (!assetPath) {
      setUrl(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const resolvedUrl = assetResolver.resolve(assetPath);
      
      if (preload) {
        // Preload and verify asset exists
        const img = new Image();
        
        await new Promise((resolve, reject) => {
          img.onload = () => {
            setUrl(resolvedUrl);
            setLoading(false);
            onLoad?.(resolvedUrl);
            resolve();
          };
          
          img.onerror = () => {
            const err = new Error(`Failed to load asset: ${assetPath}`);
            setError(err);
            setLoading(false);
            onError?.(err);
            
            // Try fallback if provided
            if (fallback) {
              setUrl(fallback);
            }
            
            reject(err);
          };
          
          img.src = resolvedUrl;
        });
      } else {
        // Just resolve URL without preloading
        setUrl(resolvedUrl);
        setLoading(false);
        onLoad?.(resolvedUrl);
      }
    } catch (err) {
      setError(err);
      setLoading(false);
      onError?.(err);
      
      if (fallback) {
        setUrl(fallback);
      }
    }
  }, [assetPath, preload, fallback, onError, onLoad]);

  const reload = useCallback(() => {
    loadAsset();
  }, [loadAsset]);

  useEffect(() => {
    loadAsset();
  }, [loadAsset]);

  return { url, loading, error, reload };
};

/**
 * Hook for batch loading multiple assets
 * @param {string[]} assetPaths - Array of asset paths
 * @param {object} options - Loading options
 * @returns {object} - { assets, loading, errors, reload }
 */
export const useAssets = (assetPaths, options = {}) => {
  const { preload = false } = options;
  
  const [loading, setLoading] = useState(true);
  const [errors, setErrors] = useState({});
  const [assets, setAssets] = useState({});

  const loadAssets = useCallback(async () => {
    if (!assetPaths?.length) {
      setAssets({});
      setLoading(false);
      return;
    }

    setLoading(true);
    setErrors({});
    
    const newAssets = {};
    const newErrors = {};

    await Promise.allSettled(
      assetPaths.map(async (assetPath) => {
        try {
          const resolvedUrl = assetResolver.resolve(assetPath);
          
          if (preload) {
            await assetResolver.preload(assetPath);
          }
          
          newAssets[assetPath] = resolvedUrl;
        } catch (err) {
          newErrors[assetPath] = err;
        }
      })
    );

    setAssets(newAssets);
    setErrors(newErrors);
    setLoading(false);
  }, [assetPaths, preload]);

  const reload = useCallback(() => {
    loadAssets();
  }, [loadAssets]);

  useEffect(() => {
    loadAssets();
  }, [loadAssets]);

  return { assets, loading, errors, reload };
};

/**
 * Hook for preloading critical assets on app startup
 * @param {string[]} criticalAssets - Assets to preload immediately
 */
export const useCriticalAssets = (criticalAssets) => {
  const [preloaded, setPreloaded] = useState(false);
  const [errors, setErrors] = useState([]);

  useEffect(() => {
    if (!criticalAssets?.length) return;

    const preloadCritical = async () => {
      try {
        await assetResolver.preloadCritical(criticalAssets);
        setPreloaded(true);
      } catch (err) {
        setErrors(prev => [...prev, err]);
      }
    };

    preloadCritical();
  }, [criticalAssets]);

  return { preloaded, errors };
};

/**
 * Simple hook that just returns resolved asset URL
 * @param {string} assetPath - Asset path
 * @returns {string} - Resolved URL
 */
export const useAssetUrl = (assetPath) => {
  const [url, setUrl] = useState(null);

  useEffect(() => {
    if (assetPath) {
      setUrl(assetResolver.resolve(assetPath));
    } else {
      setUrl(null);
    }
  }, [assetPath]);

  return url;
};