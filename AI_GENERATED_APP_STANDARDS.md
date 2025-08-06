# Standards for AI-Generated Apps

## Tech Stack (REQUIRED for all generated apps)

### Frontend
- **Framework**: React 18+ with Vite
- **Language**: TypeScript (mandatory)
- **Styling**: Tailwind CSS
- **State Management**: Zustand
- **Routing**: React Router v6
- **Forms**: React Hook Form + Zod validation
- **UI Components**: shadcn/ui components

### Backend & Deployment
- **Runtime**: Cloudflare Workers (NOT Node.js)
- **Database**: Supabase PostgreSQL (with RLS)
- **Auth**: Supabase Auth
- **File Storage**: Supabase Storage
- **Background Jobs**: Supabase Edge Functions (Deno)
- **Payments**: Stripe (when needed)

### Required Files Structure
```
/
├── src/
│   ├── index.tsx           # Main entry point
│   ├── App.tsx            # Root component
│   ├── lib/
│   │   ├── supabase.ts    # Supabase client with RLS
│   │   └── analytics.ts   # Overskill analytics
│   ├── components/        # React components
│   ├── hooks/            # Custom hooks
│   └── styles/
│       └── globals.css    # Tailwind imports
├── public/
│   └── index.html
├── package.json
├── tsconfig.json
├── vite.config.ts
├── tailwind.config.js
├── postcss.config.js
└── wrangler.toml          # Cloudflare Workers config
```

## Critical Requirements

### 1. Supabase Integration with RLS
Every generated app MUST include this exact pattern:

```typescript
// src/lib/supabase.ts
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

// CRITICAL: Set RLS context before any database operation
export const setRLSContext = async (userId: string) => {
  const { error } = await supabase.rpc('set_config', {
    setting_name: 'app.current_user_id',
    new_value: userId,
    is_local: true
  });
  if (error) throw error;
};

// Initialize RLS on app load
export const initializeApp = async () => {
  const ownerId = import.meta.env.VITE_OWNER_ID;
  if (ownerId) {
    await setRLSContext(ownerId);
  }
};
```

### 2. Analytics Auto-Injection
Every app MUST include analytics:

```typescript
// src/lib/analytics.ts
class OverskillAnalytics {
  private appId: string;
  
  constructor() {
    this.appId = import.meta.env.VITE_APP_ID || 'unknown';
    this.track('page_view', {
      url: window.location.href,
      referrer: document.referrer
    });
  }
  
  track(event: string, data: Record<string, any> = {}) {
    fetch('https://overskill.app/api/v1/analytics/track', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        app_id: this.appId,
        event,
        data,
        timestamp: Date.now()
      })
    }).catch(() => {}); // Silent fail
  }
}

// Auto-initialize
export const analytics = new OverskillAnalytics();
```

### 3. Environment Variables
Required in every wrangler.toml:

```toml
name = "app-{{APP_ID}}"
main = "dist/index.js"
compatibility_date = "2024-08-01"

[env.production.vars]
VITE_SUPABASE_URL = "{{SUPABASE_URL}}"
VITE_SUPABASE_ANON_KEY = "{{SUPABASE_ANON_KEY}}"
VITE_APP_ID = "{{APP_ID}}"
VITE_OWNER_ID = "{{OWNER_ID}}"
VITE_ANALYTICS_ENABLED = "true"
```

### 4. Package.json Requirements
```json
{
  "name": "overskill-app",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "deploy": "npm run build && wrangler deploy"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.39.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.20.0",
    "zustand": "^4.4.0",
    "react-hook-form": "^7.48.0",
    "zod": "^3.22.0",
    "@radix-ui/react-*": "latest"
  },
  "devDependencies": {
    "@types/react": "^18.2.43",
    "@types/react-dom": "^18.2.17",
    "@vitejs/plugin-react": "^4.2.1",
    "typescript": "^5.3.0",
    "vite": "^5.0.8",
    "tailwindcss": "^3.4.0",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32",
    "wrangler": "^3.0.0"
  }
}
```

### 5. TypeScript Config
```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

## Code Quality Requirements

### 1. Error Handling
- Every async operation MUST have try-catch
- Loading states for all data fetching
- User-friendly error messages
- Fallback UI for errors

### 2. Performance
- React.memo for expensive components
- useMemo/useCallback where appropriate
- Lazy loading for routes
- Image optimization

### 3. Accessibility
- Semantic HTML
- ARIA labels where needed
- Keyboard navigation support
- Focus management

### 4. Security
- No hardcoded secrets
- Input sanitization
- XSS prevention
- CORS properly configured

## UI/UX Requirements

### 1. Responsive Design
- Mobile-first approach
- Breakpoints: sm(640px), md(768px), lg(1024px), xl(1280px)
- Touch-friendly on mobile
- Proper viewport meta tag

### 2. Dark Mode
- System preference detection
- Manual toggle option
- Persistent preference in localStorage
- Smooth transitions

### 3. Loading States
- Skeleton screens for content
- Spinners for actions
- Progress bars for uploads
- Optimistic updates where possible

## Supabase Edge Functions

When background processing is needed:

```typescript
// supabase/functions/process-task/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const { appId, userId, task } = await req.json();
  
  // Initialize Supabase client
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  );
  
  // Set RLS context
  await supabase.rpc('set_config', {
    setting_name: 'app.current_user_id',
    new_value: userId,
    is_local: true
  });
  
  // Process task
  try {
    // Task logic here
    return new Response(JSON.stringify({ success: true }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});
```

## Database Schema Pattern

Apps should use these standard tables:

```sql
-- User data (if auth enabled)
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  name text,
  avatar_url text,
  created_at timestamptz DEFAULT now()
);

-- App-specific data
CREATE TABLE app_data (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES users(id) ON DELETE CASCADE,
  data jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Enable RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_data ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view own profile" ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON users
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can view own data" ON app_data
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own data" ON app_data
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own data" ON app_data
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own data" ON app_data
  FOR DELETE USING (auth.uid() = user_id);
```

## DO NOT Generate

- Node.js specific code (fs, path, etc.)
- Express/Koa/Fastify servers
- MongoDB/MySQL/raw PostgreSQL
- Firebase (use Supabase instead)
- NextAuth (use Supabase Auth)
- Redux (use Zustand)
- Material-UI/Ant Design (use shadcn/ui)
- Axios (use native fetch)

## Testing Checklist

Every generated app should:
- [ ] Build successfully with `npm run build`
- [ ] Deploy to Cloudflare Workers
- [ ] Connect to Supabase with RLS
- [ ] Track analytics events
- [ ] Handle errors gracefully
- [ ] Work on mobile devices
- [ ] Support dark mode
- [ ] Load in under 3 seconds