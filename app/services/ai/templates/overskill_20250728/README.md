# OverSkill App Template

This is the base template for OverSkill AI-generated applications. It includes all the necessary integrations and UI components for building production-ready apps.

## Features

- **React 18+ with TypeScript** - Modern React with full TypeScript support
- **Vite** - Lightning-fast build tool
- **Tailwind CSS** - Utility-first CSS framework
- **shadcn/ui Components** - Beautiful, accessible UI components
- **Supabase Integration** - Database with Row-Level Security (RLS)
- **Analytics** - Built-in OverSkill analytics tracking
- **Cloudflare Workers** - Edge deployment ready
- **Dark Mode** - System preference detection and manual toggle

## Structure

```
/
├── src/
│   ├── components/     # Reusable React components
│   │   └── ui/        # shadcn/ui components
│   ├── hooks/         # Custom React hooks
│   ├── lib/           # Utilities and integrations
│   │   ├── analytics.ts   # OverSkill analytics
│   │   ├── supabase.ts   # Supabase client with RLS
│   │   └── utils.ts      # Helper functions
│   ├── pages/         # Page components
│   ├── App.tsx        # Main app component
│   ├── main.tsx       # Entry point
│   └── index.css      # Global styles
├── public/            # Static assets
├── index.html         # HTML template
├── package.json       # Dependencies
├── tsconfig.json      # TypeScript config
├── vite.config.ts     # Vite configuration
├── tailwind.config.ts # Tailwind configuration
└── wrangler.toml      # Cloudflare Workers config
```

## Key Integrations

### Supabase with RLS

Every app includes Row-Level Security setup:

```typescript
// Initialize on app load
await initializeApp();

// For authenticated operations
await withRLS(userId, async () => {
  // Your database operations here
});
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

### UI Components

All shadcn/ui components are included:
- Accordion, Alert, Avatar, Badge
- Button, Card, Checkbox, Dialog
- Form controls, Inputs, Selects
- Navigation, Tabs, Toast notifications
- And many more...

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

## Environment Variables

Required in wrangler.toml:
- `VITE_SUPABASE_URL` - Supabase project URL
- `VITE_SUPABASE_ANON_KEY` - Supabase anonymous key
- `VITE_APP_ID` - OverSkill app ID
- `VITE_OWNER_ID` - App owner ID
- `VITE_ANALYTICS_ENABLED` - Enable/disable analytics

## Agent Loop Support

This template is designed to work with the OverSkill AI agent loop system, supporting:
- Iterative development
- Goal tracking
- Progress verification
- Error recovery
- Context preservation

The structure allows the AI agent to make multiple passes, verify work, and iterate until completion.
