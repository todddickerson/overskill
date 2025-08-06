/**
 * Cloudflare Worker Template for OverSkill Apps
 * Handles secure environment variables and serves app files
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    // Handle API requests that need secret env vars
    if (path.startsWith('/api/')) {
      return handleApiRequest(request, env);
    }
    
    // Serve static files with public env vars injected
    return serveStaticFile(path, env);
  },
};

/**
 * Handle API requests with access to secret environment variables
 */
async function handleApiRequest(request, env) {
  const url = new URL(request.url);
  const path = url.pathname;
  
  // Example: Supabase proxy endpoint
  if (path === '/api/supabase') {
    const supabaseUrl = env.SUPABASE_URL;
    const supabaseKey = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY;
    
    if (!supabaseUrl || !supabaseKey) {
      return new Response('Database not configured', { status: 503 });
    }
    
    // Proxy the request to Supabase with authentication
    const supabaseRequest = new Request(
      supabaseUrl + url.search,
      request
    );
    supabaseRequest.headers.set('apikey', supabaseKey);
    supabaseRequest.headers.set('Authorization', `Bearer ${supabaseKey}`);
    
    return fetch(supabaseRequest);
  }
  
  // Example: OpenAI proxy endpoint
  if (path === '/api/openai') {
    const openaiKey = env.OPENAI_API_KEY;
    
    if (!openaiKey) {
      return new Response('AI service not configured', { status: 503 });
    }
    
    // Proxy to OpenAI with authentication
    const openaiRequest = new Request(
      'https://api.openai.com/v1' + path.replace('/api/openai', ''),
      request
    );
    openaiRequest.headers.set('Authorization', `Bearer ${openaiKey}`);
    
    return fetch(openaiRequest);
  }
  
  // Example: Stripe proxy endpoint
  if (path.startsWith('/api/stripe')) {
    const stripeKey = env.STRIPE_SECRET_KEY;
    
    if (!stripeKey) {
      return new Response('Payment service not configured', { status: 503 });
    }
    
    // Proxy to Stripe with authentication
    const stripeRequest = new Request(
      'https://api.stripe.com/v1' + path.replace('/api/stripe', ''),
      request
    );
    stripeRequest.headers.set('Authorization', `Bearer ${stripeKey}`);
    
    return fetch(stripeRequest);
  }
  
  return new Response('API endpoint not found', { status: 404 });
}

/**
 * Serve static files with public environment variables injected
 */
async function serveStaticFile(path, env) {
  // Get the file content from KV storage or R2
  // This is a simplified example - actual implementation would fetch from storage
  const fileContent = await getFileContent(path);
  
  if (!fileContent) {
    return new Response('File not found', { status: 404 });
  }
  
  // For HTML files, inject public environment variables
  if (path.endsWith('.html') || path === '/') {
    const publicEnvVars = getPublicEnvVars(env);
    const envScript = `
      <script>
        // Public environment variables injected by Cloudflare Worker
        window.ENV = ${JSON.stringify(publicEnvVars)};
      </script>
    `;
    
    // Inject before closing </head> or at the beginning of <body>
    let modifiedContent = fileContent;
    if (fileContent.includes('</head>')) {
      modifiedContent = fileContent.replace('</head>', envScript + '</head>');
    } else if (fileContent.includes('<body>')) {
      modifiedContent = fileContent.replace('<body>', '<body>' + envScript);
    } else {
      modifiedContent = envScript + fileContent;
    }
    
    return new Response(modifiedContent, {
      headers: {
        'Content-Type': 'text/html',
        'Cache-Control': 'no-cache',
      },
    });
  }
  
  // Serve other files as-is
  const contentType = getContentType(path);
  return new Response(fileContent, {
    headers: {
      'Content-Type': contentType,
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

/**
 * Get only public environment variables (non-secret)
 */
function getPublicEnvVars(env) {
  const publicVars = {};
  
  // These are safe to expose to the client
  const publicKeys = [
    'APP_ID',
    'ENVIRONMENT',
    'API_BASE_URL',
    'SUPABASE_URL',  // Public URL is safe
    'SUPABASE_ANON_KEY',  // Anon key is meant to be public (RLS protects data)
    'STRIPE_PUBLISHABLE_KEY',  // Publishable key is meant to be public
    'PUBLIC_*',  // Any key starting with PUBLIC_
  ];
  
  for (const key in env) {
    // Check if this key should be public
    const isPublic = publicKeys.some(pattern => {
      if (pattern.endsWith('*')) {
        return key.startsWith(pattern.slice(0, -1));
      }
      return key === pattern;
    });
    
    if (isPublic) {
      publicVars[key] = env[key];
    }
  }
  
  return publicVars;
}

/**
 * Get file content (simplified - would use KV or R2 in production)
 */
async function getFileContent(path) {
  // In production, this would fetch from Cloudflare KV or R2
  // For now, return a placeholder
  const files = {
    '/': '<html><head></head><body><h1>App</h1></body></html>',
    '/index.html': '<html><head></head><body><h1>App</h1></body></html>',
    '/app.js': 'console.log("App loaded");',
    '/styles.css': 'body { font-family: sans-serif; }',
  };
  
  return files[path] || files['/'];
}

/**
 * Get content type for file
 */
function getContentType(path) {
  const ext = path.split('.').pop();
  const types = {
    'html': 'text/html',
    'js': 'application/javascript',
    'css': 'text/css',
    'json': 'application/json',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'svg': 'image/svg+xml',
    'ico': 'image/x-icon',
  };
  
  return types[ext] || 'text/plain';
}