// R2 Asset Resolver for OverSkill Generated Apps
// Handles dynamic asset URL resolution between development and production
// Based on Cloudflare R2 bucket strategy

class AssetResolver {
  constructor() {
    // Get app-specific configuration from environment or embedded config
    this.appId = typeof window !== 'undefined' && window.APP_CONFIG?.APP_ID || process.env.VITE_APP_ID;
    this.environment = typeof window !== 'undefined' && window.APP_CONFIG?.ENVIRONMENT || process.env.VITE_ENVIRONMENT || 'production';
    
    // R2 Configuration
    this.r2BaseUrl = typeof window !== 'undefined' && window.APP_CONFIG?.R2_BASE_URL || process.env.VITE_R2_BASE_URL || 'https://pub.overskill.com';
    this.useLocalAssets = typeof window !== 'undefined' && window.APP_CONFIG?.USE_LOCAL_ASSETS || process.env.VITE_USE_LOCAL_ASSETS === 'true';
    
    // Cache for resolved URLs
    this.urlCache = new Map();
  }

  /**
   * Resolve asset path to full URL
   * @param {string} assetPath - Relative path like 'images/hero.jpg' or '/assets/logo.png'
   * @returns {string} - Full URL to asset
   */
  resolve(assetPath) {
    // Return cached URL if available
    if (this.urlCache.has(assetPath)) {
      return this.urlCache.get(assetPath);
    }

    let resolvedUrl;

    if (this.useLocalAssets) {
      // Development: Use local assets from public folder
      resolvedUrl = this.resolveLocal(assetPath);
    } else {
      // Production: Use R2 bucket URL  
      resolvedUrl = this.resolveR2(assetPath);
    }

    // Cache the resolved URL
    this.urlCache.set(assetPath, resolvedUrl);
    return resolvedUrl;
  }

  /**
   * Resolve to local asset URL for development
   */
  resolveLocal(assetPath) {
    const cleanPath = assetPath.replace(/^\/+/, ''); // Remove leading slashes
    return `/${cleanPath}`;
  }

  /**
   * Resolve to R2 bucket URL for production
   */
  resolveR2(assetPath) {
    const cleanPath = assetPath.replace(/^\/+/, ''); // Remove leading slashes
    
    // Handle different input formats
    let finalPath = cleanPath;
    
    // If path doesn't start with 'assets/', add it
    if (!cleanPath.startsWith('assets/') && !cleanPath.startsWith('app-')) {
      finalPath = `assets/${cleanPath}`;
    }
    
    // Construct R2 URL: https://pub.overskill.com/app-{id}/production/{path}
    return `${this.r2BaseUrl}/app-${this.appId}/production/${finalPath}`;
  }

  /**
   * Preload an asset for better performance
   */
  preload(assetPath, as = 'image') {
    if (typeof document === 'undefined') return Promise.resolve();
    
    const url = this.resolve(assetPath);
    const link = document.createElement('link');
    link.rel = 'preload';
    link.href = url;
    link.as = as;
    
    return new Promise((resolve, reject) => {
      link.onload = resolve;
      link.onerror = reject;
      document.head.appendChild(link);
    });
  }

  /**
   * Get asset URL with error handling and fallback
   */
  getAssetUrl(assetPath, fallback = null) {
    try {
      return this.resolve(assetPath);
    } catch (error) {
      console.warn(`Failed to resolve asset: ${assetPath}`, error);
      return fallback || `/${assetPath}`;
    }
  }

  /**
   * Batch preload critical assets
   */
  async preloadCritical(assetPaths) {
    const promises = assetPaths.map(path => this.preload(path).catch(err => {
      console.warn(`Failed to preload: ${path}`, err);
    }));
    
    await Promise.allSettled(promises);
  }

  /**
   * Debug helper - log asset resolution
   */
  debug(assetPath) {
    console.log(`[AssetResolver] ${assetPath} -> ${this.resolve(assetPath)}`, {
      appId: this.appId,
      environment: this.environment,
      r2BaseUrl: this.r2BaseUrl,
      useLocalAssets: this.useLocalAssets
    });
  }
}

// Create singleton instance
const assetResolver = new AssetResolver();

// Export for different module systems
if (typeof module !== 'undefined' && module.exports) {
  // CommonJS
  module.exports = { assetResolver, AssetResolver };
} else if (typeof window !== 'undefined') {
  // Browser global
  window.assetResolver = assetResolver;
}

export { assetResolver, AssetResolver };
export default assetResolver;