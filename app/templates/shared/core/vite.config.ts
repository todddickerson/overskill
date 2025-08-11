import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  
  // Build configuration optimized for Cloudflare Workers
  build: {
    // Target ES2022 for modern browsers
    target: 'es2022',
    
    // Optimize for size (Cloudflare 1MB limit)
    minify: 'esbuild',
    
    // Generate source maps for debugging
    sourcemap: true,
    
    // Split chunks for better caching
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ['react', 'react-dom'],
          router: ['react-router-dom'],
          supabase: ['@supabase/supabase-js']
        }
      }
    }
  },
  
  // Development server configuration
  server: {
    port: 3000,
    open: true
  },
  
  // Environment variable handling
  envPrefix: 'VITE_',
  
  // Path resolution
  resolve: {
    alias: {
      '@': '/src'
    }
  }
})