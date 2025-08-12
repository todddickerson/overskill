// App ID: 105 | Built: 2025-08-12T18:58:48Z | Mode: hybrid
// Architecture: CSS embedded, JS assets served with correct MIME types

// HTML with embedded CSS and external JS references
const HTML_CONTENT = `\u003c!DOCTYPE html\u003e\n\u003chtml\u003e\n\u003chead\u003e\n  \u003ctitle\u003eHello from App 105\u003c/title\u003e\n\u003c/head\u003e\n\u003cbody\u003e\n  \u003ch1\u003eHello World!\u003c/h1\u003e\n  \u003cp\u003eApp 105 deployed at 2025-08-12 18:58:22 UTC\u003c/p\u003e\n  \u003cp\u003eCloudflare deployment test successful!\u003c/p\u003e\n\u003c/body\u003e\n\u003c/html\u003e\n`;

// External assets (JS files) with content and MIME types
const ASSETS = {

};

// Debug: Log available assets on Worker initialization
console.log('[Worker Init] App 105 - Available assets:', Object.keys(ASSETS));

// Service Worker event listener
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const url = new URL(request.url);
  
  // Get environment variables with fallbacks
  const config = {
    supabaseUrl: typeof SUPABASE_URL !== 'undefined' ? SUPABASE_URL : 'https://bsbgwixlklvgeoxvjmtb.supabase.co',
    supabaseAnonKey: typeof SUPABASE_ANON_KEY !== 'undefined' ? SUPABASE_ANON_KEY : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzYmd3aXhsa2x2Z2VveHZqbXRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM3MzgyMTAsImV4cCI6MjA2OTMxNDIxMH0.0K9JFMA0K90yOtvnYSYBCroS2Htg1iaICjcevNVCWKM',
    appId: typeof APP_ID !== 'undefined' ? APP_ID : '105',
    environment: typeof ENVIRONMENT !== 'undefined' ? ENVIRONMENT : 'preview',
    customVars: {}
  };
  
  // CRITICAL FIX: Serve JS assets with correct MIME types
  // Handle both absolute (/assets/file.js) and relative (./file.js) import paths
  let assetPath = null;
  
  if (url.pathname.startsWith('/assets/') && url.pathname.endsWith('.js')) {
    // Direct absolute path request
    assetPath = url.pathname;
  } else if (url.pathname.endsWith('.js')) {
    // Relative path - convert to absolute
    const filename = url.pathname.split('/').pop();
    // Find matching asset by filename
    assetPath = Object.keys(ASSETS).find(path => path.endsWith('/' + filename));
  }
  
  if (assetPath && ASSETS[assetPath]) {
    const asset = ASSETS[assetPath];
    console.log('[Worker] Serving JS asset:', assetPath, 'type:', asset.type);
    return new Response(asset.content, {
      headers: {
        'Content-Type': asset.type || 'application/javascript; charset=utf-8',
        'Cache-Control': 'public, max-age=31536000', // 1 year cache for assets
        'Access-Control-Allow-Origin': '*'
      }
    });
  }
  
  // Check if this is a JS file request that we should handle
  if (url.pathname.endsWith('.js')) {
    console.log('[Worker] JS asset not found:', url.pathname);
    console.log('[Worker] Available assets:', Object.keys(ASSETS));
    return new Response('JavaScript asset not found: ' + url.pathname + '
Available: ' + Object.keys(ASSETS).join(', '), { 
      status: 404,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
  
  // Handle API routes  
  if (url.pathname.startsWith('/api/')) {
    return new Response(JSON.stringify({
      message: 'API endpoint',
      appId: config.appId,
      path: url.pathname
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
  
  // Inject config and serve HTML for all page routes
  const configScript = '<script>window.APP_CONFIG=' + JSON.stringify(config) + ';</script>';
  const finalHtml = HTML_CONTENT.replace('<div id="root">', configScript + '<div id="root">');
  
  return new Response(finalHtml, {
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'public, max-age=300'
    }
  });
}
