# Build Strategy for Fast Previews

## The Problem
- Full Vite builds take 30-60+ seconds
- Users expect instant previews (< 5 seconds)
- TypeScript compilation adds overhead
- Node modules installation is slow

## Our Solution: Hybrid Approach

### 1. **Instant Preview Mode** (Default) ✨
**Time: < 3 seconds**

```javascript
// Use ESBuild in the browser via CDN
<script src="https://unpkg.com/esbuild-wasm@0.19.0/lib/browser.min.js"></script>
<script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>

// Transform TypeScript to JS on-the-fly in Worker
const transformed = await esbuild.transform(tsxCode, {
  loader: 'tsx',
  target: 'es2020'
})
```

**How it works:**
- TypeScript/JSX compiled in Cloudflare Worker using esbuild-wasm
- React loaded via CDN
- No build step, instant deployment
- Perfect for development/preview

### 2. **Production Build Mode** (Optional) 🚀
**Time: 30-60 seconds**

- Full Vite build with optimizations
- Tree shaking, minification, code splitting
- Triggered manually or on "Publish"
- Runs in background, doesn't block preview

## Implementation Plan

### Phase 1: Fast Preview System (This Week)
```javascript
// CloudflarePreviewService modification
class FastPreviewService {
  async deployPreview(app) {
    // 1. Transform TSX to JS in Worker
    const files = await transformFiles(app.files)
    
    // 2. Inject React CDN
    files['index.html'] = injectCDNs(files['index.html'])
    
    // 3. Deploy immediately
    return deployToWorker(files) // < 3 seconds
  }
}
```

### Phase 2: Background Builds (Next Week)
```javascript
// Only for production deployment
class ProductionBuildService {
  async buildForProduction(app) {
    // Run Vite build in container/Lambda
    // Store artifacts in R2
    // Deploy optimized version
  }
}
```

## Fast Transform Implementation

### Option 1: ESBuild in Worker (Fastest)
```javascript
// Cloudflare Worker with esbuild-wasm
import * as esbuild from 'esbuild-wasm'
import esbuildWasmUrl from 'esbuild-wasm/esbuild.wasm?url'

let esbuildInitialized = false

async function initEsbuild() {
  if (!esbuildInitialized) {
    await esbuild.initialize({
      wasmURL: esbuildWasmUrl,
    })
    esbuildInitialized = true
  }
}

export default {
  async fetch(request, env) {
    await initEsbuild()
    
    // Transform TypeScript/JSX
    const result = await esbuild.transform(code, {
      loader: 'tsx',
      jsx: 'automatic',
      jsxImportSource: 'react'
    })
    
    return new Response(result.code)
  }
}
```

### Option 2: Babel Standalone (Simpler)
```javascript
// Use Babel in the browser
<script type="text/babel" data-type="module">
  import React from 'https://esm.sh/react@18'
  import ReactDOM from 'https://esm.sh/react-dom@18'
  
  // Your TypeScript/JSX code here
  const App = () => <div>Hello</div>
</script>
```

### Option 3: SWC WASM (Modern)
```javascript
// Use SWC for faster transforms
import initSwc, { transformSync } from '@swc/wasm-web'

await initSwc()
const output = transformSync(typescriptCode, {
  jsc: {
    parser: { syntax: 'typescript', tsx: true },
    transform: { react: { runtime: 'automatic' } }
  }
})
```

## CDN Dependencies

Instead of npm install, use CDN imports:

```javascript
// Before (requires build)
import React from 'react'
import { createClient } from '@supabase/supabase-js'

// After (instant)
import React from 'https://esm.sh/react@18'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
```

## Performance Targets

| Mode | Time | Use Case |
|------|------|----------|
| Preview (CDN + Transform) | < 3s | Development, testing |
| Fast Deploy (Pre-transformed) | < 5s | Quick iterations |
| Production Build | 30-60s | Final deployment |

## Benefits

1. **Instant Gratification**: Users see results in seconds
2. **No Build Queue**: Transform happens in Worker
3. **Cost Effective**: No build servers needed
4. **Progressive Enhancement**: Can upgrade to full build later

## Trade-offs

### Preview Mode
✅ Instant (< 3s)
✅ No build infrastructure
✅ Simple to implement
❌ Larger bundle sizes
❌ No tree shaking
❌ Slower runtime performance

### Production Mode
✅ Optimized bundles
✅ Tree shaking
✅ Better performance
❌ Slow builds (30-60s)
❌ Complex infrastructure
❌ Higher costs

## Recommendation

**Start with Fast Preview Mode**:
1. Implement esbuild-wasm in Worker
2. Use React/libraries via CDN
3. Transform on-the-fly
4. Deploy instantly

**Add Production Builds Later**:
- Only when user clicks "Publish to Production"
- Run in background
- Use for final deployment

This gives us the best of both worlds:
- **Fast iteration** during development (< 3s)
- **Optimized apps** in production (when it matters)