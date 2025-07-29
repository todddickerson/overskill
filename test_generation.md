# Testing AI App Generation - Full App Creation

## Setup Steps

1. Start Rails server: `rails server`
2. Start Sidekiq for background jobs: `bundle exec sidekiq`
3. Ensure you have OPENROUTER_API_KEY in .env.development.local

## Test Scenarios

### Todo List App
1. Navigate to http://localhost:3000
2. Sign in/sign up 
3. Go to Apps section
4. Click "New App"
5. Enter:
   - Name: "Task Master"
   - Prompt: "Create a todo list app with categories, due dates, and priority levels. Use a modern purple theme."
   - App Type: tool
   - Framework: react or vanilla
   - Base Price: 0

### Game App
- Name: "Memory Match"
- Prompt: "Build a memory card matching game with emojis. Include score tracking, timer, and difficulty levels."
- App Type: game
- Framework: vanilla

### Landing Page
- Name: "SaaS Landing"
- Prompt: "Create a landing page for a project management SaaS tool. Include hero section, features, pricing table, and testimonials."
- App Type: landing_page
- Framework: vanilla or react

### Dashboard
- Name: "Sales Dashboard"
- Prompt: "Build an analytics dashboard showing revenue charts, customer metrics, and growth trends. Dark theme with interactive filters."
- App Type: dashboard
- Framework: react

## What the System Does
- Analyzes your prompt to determine app type
- Uses specialized prompt templates for better results
- Generates complete, working applications with:
  - All necessary HTML, CSS, and JavaScript files
  - Modern, professional design
  - Responsive layout for all devices
  - Interactive features specific to the app type
  - Proper code organization and comments

## Expected Results
- Todo apps: Full CRUD operations, localStorage, categories
- Games: Game loop, scoring, levels, smooth animations
- Landing pages: Sections, animations, forms, responsive
- Dashboards: Charts, data visualizations, filters

## What to Check

- Generation status updates in real-time
- Files are created and stored
- Error handling if generation fails
- Cost tracking is recorded

## Common Issues

1. Missing OPENROUTER_API_KEY - Add to .env.development.local
2. Sidekiq not running - Start with `bundle exec sidekiq`
3. Redis not running - Start with `redis-server`