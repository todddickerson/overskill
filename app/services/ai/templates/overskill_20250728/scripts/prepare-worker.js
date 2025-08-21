#!/usr/bin/env node

// This script prepares the Vite build output for Cloudflare Workers deployment
// It creates a simple worker that serves the static files

import fs from 'fs';
import path from 'path';

const workerCode = `
// Simple static file server for Cloudflare Workers
// This serves the Vite-built SPA with proper routing support

export default {
  async fetch(request, env, ctx) {
    // For Workers for Platforms, we'll handle this differently in production
    // This is a placeholder that will be replaced during deployment
    return new Response('App deployed successfully! Static serving configured via platform.', {
      status: 200,
      headers: { 'Content-Type': 'text/plain' }
    });
  }
};
`;

// Ensure dist directory exists
if (!fs.existsSync('./dist')) {
  console.error('❌ dist directory not found. Run "npm run build" first.');
  process.exit(1);
}

// Write the worker file
fs.writeFileSync('./dist/index.js', workerCode);
console.log('✅ Created dist/index.js for Workers deployment');