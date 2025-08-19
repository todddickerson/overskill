// Lazy Loading Image Component for R2 Assets
// Optimized for performance with intersection observer and error handling

import React, { useState, useRef, useEffect, forwardRef } from 'react';
import { useAsset } from './useAsset';

/**
 * Lazy loading image component with R2 asset resolver
 * Only loads image when it comes into viewport
 */
const LazyImage = forwardRef(({
  src,
  alt = '',
  className = '',
  placeholderClassName = '',
  errorClassName = '',
  onLoad = null,
  onError = null,
  threshold = 0.1,
  rootMargin = '50px',
  fallbackSrc = null,
  loadingComponent: LoadingComponent = null,
  errorComponent: ErrorComponent = null,
  ...props
}, ref) => {
  const [isVisible, setIsVisible] = useState(false);
  const imgRef = useRef();
  const [hasIntersected, setHasIntersected] = useState(false);
  
  // Use our asset resolver hook only when image is visible
  const { url, loading, error } = useAsset(
    hasIntersected ? src : null, 
    { 
      preload: true,
      fallback: fallbackSrc,
      onLoad,
      onError
    }
  );

  // Intersection Observer for lazy loading
  useEffect(() => {
    const currentImgRef = imgRef.current;
    if (!currentImgRef || hasIntersected) return;

    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setIsVisible(true);
          setHasIntersected(true);
          observer.disconnect();
        }
      },
      {
        threshold,
        rootMargin
      }
    );

    observer.observe(currentImgRef);

    return () => {
      observer.disconnect();
    };
  }, [threshold, rootMargin, hasIntersected]);

  // Default loading component
  const DefaultLoading = () => (
    <div className={`bg-gray-200 animate-pulse flex items-center justify-center ${placeholderClassName}`}>
      <svg className="w-8 h-8 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
      </svg>
    </div>
  );

  // Default error component
  const DefaultError = () => (
    <div className={`bg-gray-100 border-2 border-dashed border-gray-300 flex items-center justify-center ${errorClassName}`}>
      <div className="text-center text-gray-500">
        <svg className="w-8 h-8 mx-auto mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <p className="text-sm">Failed to load</p>
      </div>
    </div>
  );

  return (
    <div 
      ref={(node) => {
        imgRef.current = node;
        if (ref) {
          if (typeof ref === 'function') {
            ref(node);
          } else {
            ref.current = node;
          }
        }
      }}
      className={className}
      {...props}
    >
      {!hasIntersected && (
        // Placeholder before intersection
        <div className={`bg-gray-100 ${placeholderClassName}`} style={{ aspectRatio: '16/9' }}>
          {/* Empty placeholder */}
        </div>
      )}
      
      {hasIntersected && loading && (
        // Loading state
        LoadingComponent ? <LoadingComponent /> : <DefaultLoading />
      )}
      
      {hasIntersected && error && (
        // Error state
        ErrorComponent ? <ErrorComponent error={error} /> : <DefaultError />
      )}
      
      {hasIntersected && !loading && !error && url && (
        // Actual image
        <img
          src={url}
          alt={alt}
          className={className}
          onLoad={() => {
            console.log(`[LazyImage] Loaded: ${src} -> ${url}`);
          }}
          onError={() => {
            console.warn(`[LazyImage] Error loading: ${src} -> ${url}`);
          }}
        />
      )}
    </div>
  );
});

LazyImage.displayName = 'LazyImage';

export default LazyImage;

/**
 * Eager loading image component (no lazy loading)
 * For above-the-fold images that should load immediately
 */
export const EagerImage = ({ src, alt = '', className = '', fallbackSrc = null, ...props }) => {
  const { url, loading, error } = useAsset(src, { 
    preload: true,
    fallback: fallbackSrc
  });

  if (loading) {
    return (
      <div className={`bg-gray-200 animate-pulse ${className}`}>
        {/* Loading placeholder */}
      </div>
    );
  }

  if (error) {
    return (
      <div className={`bg-gray-100 border border-gray-300 flex items-center justify-center ${className}`}>
        <span className="text-gray-500 text-sm">Image failed to load</span>
      </div>
    );
  }

  return (
    <img 
      src={url} 
      alt={alt} 
      className={className}
      {...props}
    />
  );
};

/**
 * Background image component with R2 support
 */
export const BackgroundImage = ({ 
  src, 
  children, 
  className = '', 
  style = {},
  fallbackSrc = null,
  ...props 
}) => {
  const { url, loading, error } = useAsset(src, { fallback: fallbackSrc });

  const backgroundStyle = {
    ...style,
    backgroundImage: url && !loading && !error ? `url(${url})` : undefined,
    backgroundSize: 'cover',
    backgroundPosition: 'center',
    backgroundRepeat: 'no-repeat'
  };

  return (
    <div 
      className={`${className} ${loading ? 'bg-gray-200 animate-pulse' : ''}`}
      style={backgroundStyle}
      {...props}
    >
      {children}
    </div>
  );
};