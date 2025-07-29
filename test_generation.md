# Testing AI App Generation MVP

## Setup Steps

1. Start Rails server: `rails server`
2. Start Sidekiq for background jobs: `bundle exec sidekiq`
3. Ensure you have OPENROUTER_API_KEY in .env.development.local

## Test Flow

1. Navigate to http://localhost:3000
2. Sign in/sign up 
3. Go to Apps section
4. Click "New App"
5. Fill in:
   - Name: "Todo List App"
   - Prompt: "Create a simple todo list app with add, edit, delete functionality"
   - App Type: tool
   - Framework: react
   - Base Price: 0
6. Click Create
7. You should be redirected to the app page showing generation status
8. Wait for generation to complete (check Sidekiq logs)
9. Once complete, you should see the generated files

## What to Check

- Generation status updates in real-time
- Files are created and stored
- Error handling if generation fails
- Cost tracking is recorded

## Common Issues

1. Missing OPENROUTER_API_KEY - Add to .env.development.local
2. Sidekiq not running - Start with `bundle exec sidekiq`
3. Redis not running - Start with `redis-server`