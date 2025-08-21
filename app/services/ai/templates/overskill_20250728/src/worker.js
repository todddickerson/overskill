// Cloudflare Worker entry point for SPA deployment
// This worker serves static assets and handles SPA routing

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // Handle API routes (if any) - these should be handled before static assets
    if (url.pathname.startsWith('/api/')) {
      // Forward API requests to your backend or handle them here
      return new Response('API endpoint not implemented', { status: 404 });
    }
    
    // For Workers deployment, we need to handle asset serving differently
    // This is a placeholder - actual implementation depends on deployment method
    
    // For now, return a basic response indicating the worker is running
    // The actual asset serving will be handled by Cloudflare's asset binding
    return env.ASSETS.fetch(request);
  }
};