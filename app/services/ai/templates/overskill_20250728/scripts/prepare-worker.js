#!/usr/bin/env node

// This script prepares the Vite build output for Cloudflare Workers deployment
// It bundles the static files into a worker that serves them

import fs from 'fs';
import path from 'path';

// Ensure dist directory exists
if (!fs.existsSync('./dist')) {
  console.error('❌ dist directory not found. Run "npm run build" first.');
  process.exit(1);
}

// Read the built index.html file
const indexHtml = fs.readFileSync('./dist/index.html', 'utf-8');

// Read all CSS and JS files from dist/assets
const assets = {};
const assetsDir = './dist/assets';
if (fs.existsSync(assetsDir)) {
  const files = fs.readdirSync(assetsDir);
  files.forEach(file => {
    const filePath = path.join(assetsDir, file);
    const content = fs.readFileSync(filePath, 'utf-8');
    assets[`/assets/${file}`] = {
      content,
      contentType: file.endsWith('.css') ? 'text/css' : 'application/javascript'
    };
  });
  console.log(`✅ Bundled ${Object.keys(assets).length} asset files`);
}

// Create the worker code with embedded assets
const workerCode = `
// Static file server for Cloudflare Workers
// Serves the Vite-built React SPA with all assets embedded

const indexHtml = ${JSON.stringify(indexHtml)};
const assets = ${JSON.stringify(assets)};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    // Serve static assets
    if (path.startsWith('/assets/')) {
      const asset = assets[path];
      if (asset) {
        return new Response(asset.content, {
          headers: {
            'Content-Type': asset.contentType,
            'Cache-Control': 'public, max-age=31536000, immutable'
          }
        });
      }
      return new Response('Asset not found', { status: 404 });
    }
    
    // Serve favicon if it exists
    if (path === '/favicon.ico' || path === '/vite.svg') {
      // Return empty favicon to avoid 404 errors
      return new Response(null, { status: 204 });
    }
    
    // For all other routes, serve the index.html (SPA routing)
    return new Response(indexHtml, {
      headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-cache'
      }
    });
  }
};
`;

// Write the worker file
fs.writeFileSync('./dist/index.js', workerCode);
console.log('✅ Created dist/index.js for Workers deployment');
console.log(`📦 Bundled index.html and ${Object.keys(assets).length} assets into worker`);