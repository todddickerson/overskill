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
    
    // Generate source maps for debugging (disable for production)
    sourcemap: process.env.NODE_ENV !== 'production',
    
    // Configure for pure embedded approach - single bundle
    rollupOptions: {
      output: {
        // Create single bundle instead of chunks for embedded deployment
        manualChunks: undefined,
        
        // Ensure consistent file naming for easier processing
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]'
      }
    },
    
    // Adjust chunk size warning limits for embedded approach
    chunkSizeWarningLimit: 1000 // 1MB limit for Cloudflare Workers
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