# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OverSkill is an AI-powered app marketplace platform built with Ruby on Rails (BulletTrain framework). It enables non-technical users to create, deploy, and monetize applications using natural language.

## Key Commands

### Development
```bash
# Initial setup (installs dependencies, creates database)
bin/setup

# Start development server (Rails, Sidekiq, JS/CSS builds)
bin/dev

# Rails console
bin/rails console

# Run database migrations
bin/rails db:migrate
```

### Testing
```bash
# Run all tests
bin/rails test

# Run specific test file
bin/rails test test/models/app_test.rb

# Run system tests
bin/rails test:system

# Run with coverage report
COVERAGE=true bin/rails test
```

### Code Quality
```bash
# Ruby linting and formatting
bundle exec standardrb --fix

# Security scan
bundle exec brakeman

# Find N+1 queries (in development)
# Bullet gem will show warnings in browser/console
```

### BulletTrain Super Scaffolding
```bash
# Generate new model with full UI
rails generate super_scaffold ModelName Team field:type{options}

# Example:
rails generate super_scaffold App Team \
  name:text_field{required} \
  prompt:text_area{required} \
  status:options{draft,generating,published,failed}
```

## Architecture

### Tech Stack
- **Framework**: Rails 8.0 with BulletTrain Pro 1.26.0
- **Database**: PostgreSQL 14+ (single database, multi-tenant via teams)
- **Background Jobs**: Sidekiq with Redis
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS
- **AI Integration**: OpenRouter API (Kimi K2 primary)
- **Deployment**: Cloudflare Workers + R2 for generated apps

### Directory Structure
```
app/
├── controllers/
│   ├── account/         # Team-scoped controllers (BulletTrain pattern)
│   ├── api/v1/         # API endpoints with JWT auth
│   └── public/         # Public-facing pages
├── models/             # All models belong to teams for multi-tenancy
├── services/           # Business logic (AI generation, deployment, etc.)
│   ├── ai/            # AI integration services
│   ├── deployment/    # App deployment to Cloudflare
│   └── marketplace/   # Commerce and viral mechanics
├── jobs/              # Background jobs (Sidekiq)
└── views/             # ERB templates with Hotwire
```

### Key Patterns

#### BulletTrain Multi-tenancy
```ruby
# All controllers inherit from account-scoped base
class Account::AppsController < Account::ApplicationController
  # current_team and current_user are available
  def index
    @apps = current_team.apps.published
  end
end

# Models belong to teams
class App < ApplicationRecord
  belongs_to :team
  include Records::Base  # BulletTrain concern
end
```

#### Service Objects
```ruby
# Complex operations use service objects
class AI::AppGeneratorService
  def initialize(team)
    @team = team
  end
  
  def generate(prompt, options = {})
    # 1. Validate and enhance prompt
    # 2. Call AI API
    # 3. Security scan results
    # 4. Create records
    # 5. Queue deployment job
  end
end
```

#### Background Jobs
```ruby
# Long-running tasks use Sidekiq
class AppGenerationJob < ApplicationJob
  queue_as :ai_generation
  
  def perform(app)
    # Generate app code via AI
    # Deploy if successful
  end
end
```

## Environment Setup

Required environment variables (copy `.env.example` to `.env`):
- `OPENROUTER_API_KEY` - AI generation
- `STRIPE_API_KEY` + `STRIPE_SECRET_KEY` - Payments (BulletTrain configured)
- `CLOUDFLARE_*` - App hosting
- `SUPABASE_*` - App data storage
- `REDIS_URL` - Background jobs

## Common Development Tasks

### Adding New Features
1. Use BulletTrain's super scaffolding for CRUD operations
2. Create service objects for complex logic
3. Add background jobs for slow operations
4. Follow existing patterns in codebase

### Database Operations
- Migrations: `bin/rails generate migration AddFieldToModel`
- Indexes: Always add for foreign keys and lookup fields
- Seeds: Development seeds in `db/seeds/development.rb`

### API Development
- Version all endpoints (v1, v2)
- Use `Api::V1::ApplicationController` as base
- JWT authentication handled by BulletTrain
- Add to `config/routes/api/v1.rb`

### Testing Guidelines
- Test files mirror app structure
- Use factories for test data (FactoryBot)
- VCR for external API calls
- System tests for critical user flows

## Important Notes

1. **Always scope to teams**: Use `current_team` in controllers
2. **Security first**: Validate all inputs, scan generated code
3. **Use existing patterns**: Check similar files before implementing
4. **Background jobs for AI**: Never call AI APIs synchronously
5. **Follow BulletTrain conventions**: Especially for controllers and models

## Debugging Tips

```ruby
# Rails console helpers
app.account_apps_path       # Test routes
app.get '/apps'            # Make requests
reload!                    # Reload code

# Check SQL queries
App.published.to_sql       # See generated SQL
App.published.explain      # Query execution plan

# Inspect background jobs
require 'sidekiq/api'
Sidekiq::Queue.new.size    # Queue size
Sidekiq::RetrySet.new.size # Failed jobs
```

## Additional Documentation

- Main docs: `/docs/` directory
- AI context: `/docs/ai-context.md` (comprehensive guide)
- Business plan: `/docs/business-plan.md`
- Architecture: `/docs/architecture.md`
- BulletTrain docs: https://bullettrain.co/docs