import { defineConfig } from "vite";
import react from "@vitejs/plugin-react-swc";
import path from "path";

// https://vitejs.dev/config/
export default defineConfig(({ mode }) => ({
  server: {
    host: "::",
    port: 8080,
  },
  plugins: [
    react(),
  ].filter(Boolean),
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  build: {
    // Generate manifest for asset mapping
    manifest: true,

    // Ensure compatibility with modern browsers and Cloudflare Workers
    target: 'es2022',
    minify: mode === 'production' ? 'terser' : 'esbuild',

    // Generate proper content-hashed filenames
    rollupOptions: {
      output: {
        // Use content hashing for cache busting
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',

        // Use standard ES modules format (default)
        // The EdgePreviewService will embed all chunks in the worker
        // and serve them with proper MIME types for module loading
        format: 'es',

        // Smart code splitting for optimal loading performance
        manualChunks: (id) => {
          // Vendor chunk for React and core dependencies
          if (id.includes('node_modules')) {
            if (id.includes('react') || id.includes('react-dom') || id.includes('react-router')) {
              return 'vendor-react';
            }
            return 'vendor';
          }
        }
      }
    },

    // Terser options for production
    terserOptions: {
      compress: {
        drop_console: mode === 'production',
        drop_debugger: true
      }
    }
  }
}));
