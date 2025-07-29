# Testing AI App Generation v1 - Hello World Apps

## Setup Steps

1. Start Rails server: `rails server`
2. Start Sidekiq for background jobs: `bundle exec sidekiq`
3. Ensure you have OPENROUTER_API_KEY in .env.development.local

## v1 Test Scenarios

### Basic Hello World
1. Navigate to http://localhost:3000
2. Sign in/sign up 
3. Go to Apps section
4. Click "New App"
5. Try the quick examples or enter:
   - Name: "Birthday Countdown"
   - Prompt: "Create a birthday countdown app with confetti colors and party theme"
   - App Type: tool
   - Framework: vanilla or react
   - Base Price: 0

### Test Different Prompts
- "Make a meditation timer with calming blue colors"
- "Build a motivational quote app with energetic orange theme"
- "Create a simple counter with a space theme and purple colors"
- "Make a hello world app for a bakery with warm brown colors"

## What v1 Does
- Takes your prompt and extracts customization ideas
- Uses Gemini Flash (fast & cheap) to customize a hello world template
- Generates a working interactive app with:
  - Custom colors based on your theme
  - Custom text and messages
  - Interactive counter functionality
  - Responsive design
  - Your chosen framework (vanilla JS or React)

## What to Check

- Generation status updates in real-time
- Files are created and stored
- Error handling if generation fails
- Cost tracking is recorded

## Common Issues

1. Missing OPENROUTER_API_KEY - Add to .env.development.local
2. Sidekiq not running - Start with `bundle exec sidekiq`
3. Redis not running - Start with `redis-server`