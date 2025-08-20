// OverSkill Dispatch Worker with DNS Conflict Protection
// Protects existing CNAMEs like dev.overskill.com from being overridden

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const hostname = url.hostname;
    const path = url.pathname;
    
    // 🛡️ DNS CONFLICT PROTECTION
    // Check for reserved subdomains that should NOT route to WFP
    if (isReservedSubdomain(hostname)) {
      return new Response('Subdomain reserved - DNS fallback active', { 
        status: 404,
        headers: {
          'X-WFP-Protected': 'true',
          'X-Reserved-Subdomain': hostname
        }
      });
    }
    
    // Parse app routing from hostname or path
    const routing = parseAppRouting(hostname, path);
    
    if (!routing.scriptName) {
      return generateLandingPage(request, env);
    }
    
    // Get the appropriate customer script from WFP namespace
    const namespace = env[`NAMESPACE_${routing.environment.toUpperCase()}`];
    if (!namespace) {
      return new Response('Namespace not configured', { status: 500 });
    }
    
    try {
      const customerScript = namespace.get(routing.scriptName);
      if (!customerScript) {
        return new Response(`App "${routing.scriptName}" not found in ${routing.environment}`, { status: 404 });
      }
      
      // Route the request to the customer script
      return await customerScript.fetch(request);
    } catch (error) {
      console.error(`Error routing to ${routing.scriptName}:`, error);
      return new Response('Internal server error', { status: 500 });
    }
  }
};

function isReservedSubdomain(hostname) {
  // 🚨 CRITICAL: Reserved subdomains that should NOT route to Workers for Platforms
  // These preserve existing DNS configurations (CNAMEs, A records, etc.)
  const reservedSubdomains = [
    'dev.overskill.com',     // 🔒 Internal Grok - PROTECTED
    'www.overskill.com',     // 🔒 Main website
    'api.overskill.com',     // 🔒 API endpoints  
    'admin.overskill.com',   // 🔒 Admin panel
    'mail.overskill.com',    // 🔒 Email services
    'blog.overskill.com',    // 🔒 Blog/content
    'docs.overskill.com',    // 🔒 Documentation
    'status.overskill.com',  // 🔒 Status page
    'support.overskill.com', // 🔒 Support portal
    'staging.overskill.com', // 🔒 Staging environment
    'test.overskill.com',    // 🔒 Testing environment
  ];
  
  return reservedSubdomains.includes(hostname.toLowerCase());
}

function parseAppRouting(hostname, path) {
  // Method 1: Subdomain routing (overskill.com custom domain)
  // Examples: abc123.overskill.com, preview-abc123.overskill.com
  if (hostname.endsWith('.overskill.com')) {
    const subdomain = hostname.replace('.overskill.com', '');
    
    if (subdomain === 'overskill' || subdomain === 'www') {
      return { scriptName: null }; // Landing page
    }
    
    // Parse environment prefix
    if (subdomain.startsWith('preview-')) {
      return {
        scriptName: subdomain.replace('preview-', ''),
        environment: 'preview'
      };
    } else if (subdomain.startsWith('staging-')) {
      return {
        scriptName: subdomain.replace('staging-', ''),
        environment: 'staging'
      };
    } else {
      return {
        scriptName: subdomain,
        environment: 'production'
      };
    }
  }
  
  // Method 2: Path routing (workers.dev fallback)
  // Examples: /app/abc123, /app/preview-abc123
  if (path.startsWith('/app/')) {
    const scriptName = path.split('/')[2];
    if (!scriptName) return { scriptName: null };
    
    // Parse environment prefix from script name
    if (scriptName.startsWith('preview-')) {
      return {
        scriptName: scriptName.replace('preview-', ''),
        environment: 'preview'
      };
    } else if (scriptName.startsWith('staging-')) {
      return {
        scriptName: scriptName.replace('staging-', ''),
        environment: 'staging'
      };
    } else {
      return {
        scriptName: scriptName,
        environment: 'production'
      };
    }
  }
  
  return { scriptName: null };
}

function generateLandingPage(request, env) {
  const url = new URL(request.url);
  const html = `<!DOCTYPE html>
<html>
  <head>
    <title>OverSkill Workers for Platforms</title>
    <style>
      body { font-family: -apple-system, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
      .header { text-align: center; margin-bottom: 40px; }
      .info { background: #f8f9fa; padding: 20px; border-radius: 8px; margin: 20px 0; }
      .routing { background: #e3f2fd; padding: 15px; border-radius: 6px; font-family: monospace; font-size: 14px; }
      .protected { background: #d4edda; border: 1px solid #c3e6cb; padding: 15px; border-radius: 6px; margin: 20px 0; }
    </style>
  </head>
  <body>
    <div class="header">
      <h1>🚀 OverSkill Workers for Platforms</h1>
      <p>Scalable application hosting with DNS protection</p>
    </div>
    
    <div class="info">
      <h2>📋 Platform Status</h2>
      <p><strong>Request URL:</strong> ${url.href}</p>
      <p><strong>Hostname:</strong> ${url.hostname}</p>
      <p><strong>Path:</strong> ${url.pathname}</p>
      <p><strong>Routing:</strong> No app script found for this URL</p>
    </div>
    
    <div class="protected">
      <h3>🛡️ DNS Protection Active</h3>
      <p><strong>Protected subdomains:</strong> dev, www, api, admin, mail, blog, docs, status, support, staging, test</p>
      <p>These subdomains preserve existing DNS configurations and will not route to WFP apps.</p>
    </div>
    
    <div class="routing">
      <strong>🔀 Supported App URL Formats:</strong><br/>
      • Production: https://{app-id}.overskill.com<br/>
      • Preview: https://preview-{app-id}.overskill.com<br/>
      • Staging: https://staging-{app-id}.overskill.com<br/>
      • Fallback: https://dispatch-worker.workers.dev/app/{app-id}
    </div>
    
    <div class="info">
      <h3>📊 Architecture</h3>
      <p><strong>Single Dispatch Worker:</strong> Routes to 50,000+ customer apps via namespaces</p>
      <p><strong>Cost Optimization:</strong> ~$25/month base vs $25,000/month for standard Workers</p>
      <p><strong>Environments:</strong> overskill-development-{preview|staging|production}</p>
    </div>
  </body>
</html>`;
  
  return new Response(html, {
    headers: { 'Content-Type': 'text/html' }
  });
}