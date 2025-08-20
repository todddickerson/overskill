# OverSkill App Template (2025 Edition)

This is the production-ready base template for OverSkill AI-generated applications. Built with a **Supabase-first**, **simple architecture** philosophy that prioritizes reliability, cost-effectiveness ($1-2/month per app), and rapid development.

## 🚀 Core Features

- **React 18+ with TypeScript** - Modern React with full TypeScript support
- **Vite + React Router** - Lightning-fast build tool with client-side routing
- **Tailwind CSS + shadcn/ui** - Beautiful, accessible UI component system
- **App-Scoped Database** - Isolated Supabase tables per application
- **R2 Asset Management** - Cloudflare R2 integration for images and static assets
- **Smart Analytics** - Built-in OverSkill usage tracking and insights
- **Cloudflare Workers** - Edge deployment with hybrid asset optimization
- **Dark Mode Support** - System preference detection and manual toggle
- **Icon Management** - Curated Lucide React icon system

## 📁 Project Structure

```
/
├── src/
│   ├── components/         # Reusable React components
│   │   └── ui/            # shadcn/ui component library
│   ├── hooks/             # Custom React hooks
│   ├── lib/               # Core utilities and integrations
│   │   ├── analytics.ts       # OverSkill analytics tracking
│   │   ├── supabase.ts       # App-scoped Supabase client
│   │   ├── common-icons.ts   # Curated Lucide React icons
│   │   └── utils.ts          # Helper functions (cn, etc.)
│   ├── pages/             # Route components
│   ├── assetResolver.js   # 🆕 R2 asset URL resolution
│   ├── useAsset.js        # 🆕 React hook for R2 assets
│   ├── LazyImage.jsx      # 🆕 Optimized image component
│   ├── App.tsx            # Main app with React Router
│   ├── main.tsx           # Application entry point
│   └── index.css          # Global Tailwind styles
├── public/                # Static assets (favicons, etc.)
├── index.html             # Vite HTML template
├── package.json           # Dependencies and scripts
├── tsconfig.json          # TypeScript configuration
├── vite.config.ts         # Vite build configuration
├── tailwind.config.ts     # Tailwind + shadcn/ui config
└── wrangler.toml          # Cloudflare Workers deployment
```

## 🔧 Key Integrations

### App-Scoped Supabase Database

Each app gets isolated database tables using the `app_${APP_ID}_${table}` naming pattern:

```typescript
// Automatic table scoping - queries app_123_todos instead of todos
const todos = await db.from('todos').select('*');

// The app-scoped client handles the table naming automatically:
// ✅ Developer writes: db.from('todos') 
// ✅ Actually queries: app_123_todos
// ✅ Built-in Row-Level Security (RLS)
// ✅ Complete data isolation between apps
```

### R2 Asset Management System

Optimized asset loading with Cloudflare R2 integration:

```typescript
import { useAsset } from '@/useAsset';
import { LazyImage } from '@/LazyImage';

// Hook for dynamic asset URLs
const { url, loading, error } = useAsset('hero-image.jpg');

// Optimized image component with lazy loading
<LazyImage 
  src="hero-image.jpg" 
  alt="Hero image"
  className="w-full h-64 object-cover"
/>

// Direct asset resolution
import { resolveAssetUrl } from '@/assetResolver';
const imageUrl = resolveAssetUrl('logo.png');
```

### Analytics

Analytics are automatically initialized and track:
- Page views
- User interactions
- Errors
- Custom events

```typescript
// Track custom events
analytics.track('custom_event', { data: 'value' });
analytics.trackClick('button_name');
analytics.trackFormSubmit('form_name');
```

### UI Components & Icons

**shadcn/ui Component Library** - Complete accessible component system:
- Accordion, Alert, Avatar, Badge, Button, Card, Checkbox
- Dialog, Form controls, Inputs, Selects, Navigation, Tabs
- Toast notifications, Tooltips, Dropdowns, and many more

**Curated Icon System** - Pre-selected Lucide React icons to prevent AI hallucination:
```typescript
import { Menu, X, Check, Shield, Star } from '@/lib/common-icons';

// ✅ Only approved icons can be imported
// ✅ Prevents "Missing import: NonExistentIcon" errors  
// ✅ Consistent icon usage across generated apps
```

## Development

```bash
# Install dependencies
npm install

# Start development server
npm run dev

# Build for production
npm run build

# Deploy to Cloudflare Workers
npm run deploy
```

## 🔐 Environment Variables

### Public Variables (Available in Browser)
Injected into HTML at build time via `wrangler.toml`:

```toml
[vars]
VITE_APP_ID = "123"
VITE_SUPABASE_URL = "https://xxx.supabase.co"
VITE_SUPABASE_ANON_KEY = "eyJ..."
VITE_OWNER_ID = "456" 
VITE_ANALYTICS_ENABLED = "true"
VITE_R2_ASSET_URL = "https://assets.yourapp.com"
VITE_ENVIRONMENT = "production"
```

### Private Secrets (Worker-Only)
Secure server-side variables never exposed to clients:

```bash
# Set via Cloudflare API (never in browser)
SUPABASE_SERVICE_KEY    # Elevated database permissions
OPENAI_API_KEY         # AI integrations
STRIPE_SECRET_KEY      # Payment processing
```

### Automatic Configuration
The deployment system automatically configures:
- App-scoped database credentials
- R2 asset bucket URLs and permissions
- Analytics tracking with proper app isolation

## 🤖 AI-First Development

This template is engineered for **AppBuilderV5** - OverSkill's advanced AI agent system:

### Agent-Optimized Architecture
- **Surgical Code Edits** - LineReplaceService enables 90% token savings vs full rewrites
- **Smart File Detection** - Template structure aids AI understanding and navigation  
- **Error Recovery** - Built-in validation and fallback mechanisms
- **Incremental Progress** - Real-time UI updates during AI generation

### AI Development Features
- **Context Preservation** - Maintains state across multiple AI iterations
- **Goal Tracking** - Automatic progress monitoring and completion detection
- **Template Consistency** - Standardized patterns for reliable AI code generation
- **Asset Integration** - AI can generate and properly link R2-hosted images

### Development Workflow
```typescript
// AI generates apps following these patterns:
1. Foundation Setup    → Template files + app-scoped database
2. Feature Development → React components + Supabase integration  
3. Asset Management    → R2 image generation + LazyImage optimization
4. Build & Deploy     → Vite build + Cloudflare Workers deployment
5. Iterative Polish   → LineReplaceService for refinements
```

## 🏗️ Architecture Philosophy

**Simple, Supabase-First Design:**
- ✅ $1-2/month operational cost per app
- ✅ No complex microservices or edge databases
- ✅ Proven, reliable technology stack  
- ✅ Optimized for AI code generation
- ✅ Scales from prototype to production

---

*Generated by OverSkill AI • Template Version: overskill_20250728*
