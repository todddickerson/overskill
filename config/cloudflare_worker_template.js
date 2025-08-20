// Simple Worker template for serving Vite-built React SPAs
// This is all we need - no Vite plugin required

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // In production, this will be replaced by Cloudflare's 
    // automatic asset serving from the dist folder
    
    // For SPAs, always return index.html for client-side routing
    // Cloudflare Workers will automatically serve the built assets
    
    return env.ASSETS.fetch(request);
  }
}

// Alternative simple approach without ASSETS binding:
/*
export default {
  async fetch(request) {
    // This will be replaced during build with actual asset serving
    return new Response("App loading...", {
      headers: { "Content-Type": "text/html" }
    });
  }
}
*/