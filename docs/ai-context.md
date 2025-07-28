# AI Development Context for OverSkill

> This file provides shared context for AI assistants (Claude, Cursor, Kimi K2) working on the OverSkill platform. Include this file in your AI tool's context for consistent development.

## 🎯 Project Overview

OverSkill is an AI-powered app marketplace platform that enables non-technical users to create, deploy, and monetize applications using natural language. Built with Ruby on Rails (BulletTrain framework) and modern web technologies.

### Core Value Proposition
- **For Creators**: Turn ideas into income-generating apps in minutes without coding
- **For Users**: Access affordable, specialized apps built by AI
- **For Platform**: 10-15% transaction fees + subscription revenue

## 🏗️ Technical Stack

### Backend
- **Framework**: Ruby on Rails 7.1+ with BulletTrain Pro
- **Database**: PostgreSQL 14+ (single database, multi-tenant)
- **Background Jobs**: Sidekiq + Redis
- **Authentication**: Devise (via BulletTrain)
- **Payments**: Stripe Connect
- **File Storage**: Cloudflare R2 + Supabase

### AI Integration
- **Primary**: Kimi K2 via OpenRouter API
- **Fallback**: DeepSeek v3 / Claude Sonnet
- **Quick Tasks**: Gemini Flash 1.5
- **Cost**: ~$0.001-0.05 per app generation

### Infrastructure
- **App Hosting**: Cloudflare Workers + R2 (static files)
- **Database**: Shared Supabase instance with RLS
- **CDN**: Cloudflare (global edge network)
- **Platform Hosting**: Render.com or Railway

### Frontend
- **UI Framework**: Hotwire (Turbo + Stimulus)
- **CSS**: Tailwind CSS
- **JavaScript**: Vanilla JS + Stimulus controllers
- **Generated Apps**: React/Vue/Next.js/Vanilla

## 📁 Project Structure

```
overskill/
├── app/
│   ├── controllers/
│   │   ├── account/                    # BulletTrain account controllers
│   │   ├── api/v1/                    # API endpoints
│   │   ├── apps_controller.rb         # App CRUD
│   │   ├── marketplace_controller.rb  # Public marketplace
│   │   └── generations_controller.rb  # AI generation
│   ├── models/
│   │   ├── app.rb                    # Core app model
│   │   ├── creator_profile.rb        # Creator profiles
│   │   └── purchase.rb               # Transactions
│   ├── services/
│   │   ├── ai/                       # AI integration
│   │   │   ├── app_generator_service.rb
│   │   │   ├── prompt_enhancer.rb
│   │   │   └── code_security_scanner.rb
│   │   ├── deployment/               # App deployment
│   │   │   ├── cloudflare_deployer.rb
│   │   │   └── preview_builder.rb
│   │   └── marketplace/              # Commerce logic
│   │       ├── pricing_engine.rb
│   │       └── viral_mechanics.rb
│   ├── jobs/                         # Background jobs
│   └── views/                        # ERB templates
├── config/
│   ├── routes.rb                     # Route definitions
│   └── credentials.yml.enc           # Encrypted secrets
├── docs/                             # Documentation
├── test/                             # Test suite
└── lib/
    └── generators/                   # Custom generators
```

## 🔧 Development Guidelines

### Code Style
- Follow Ruby Style Guide (enforced by Standard)
- Use BulletTrain's conventions for controllers/models
- Prefer service objects for complex business logic
- Keep controllers thin, models focused

### BulletTrain Patterns
```ruby
# Always use account-scoped controllers
class Account::AppsController < Account::ApplicationController
  # BulletTrain provides current_team, current_user
  
  def index
    @apps = current_team.apps.published
  end
end

# API controllers follow versioning
class Api::V1::AppsController < Api::V1::ApplicationController
  # Automatic JWT authentication
end

# Models belong to teams for multi-tenancy
class App < ApplicationRecord
  belongs_to :team
  belongs_to :creator_profile
  
  # Use BulletTrain's concerns
  include Records::Base
  include Sortable
  include Filterable
end
```

### AI Generation Pattern
```ruby
# Always use service objects for AI calls
class AI::AppGeneratorService
  def initialize(user, team)
    @user = user
    @team = team
  end
  
  def generate(prompt, options = {})
    # 1. Enhance prompt
    enhanced = PromptEnhancer.enhance(prompt, options)
    
    # 2. Call AI API
    response = call_kimi_k2(enhanced)
    
    # 3. Process response
    app_data = process_response(response)
    
    # 4. Security scan
    scan_results = CodeSecurityScanner.scan(app_data[:files])
    
    # 5. Create records
    create_app_with_files(app_data) if scan_results[:safe]
  end
end
```

### Database Patterns
```ruby
# Use concerns for shared behavior
module Monetizable
  extend ActiveSupport::Concern
  
  included do
    has_many :purchases
    has_many :flash_sales
    
    scope :free, -> { where(base_price: 0) }
    scope :paid, -> { where('base_price > ?', 0) }
  end
  
  def current_price
    active_flash_sale? ? flash_sale_price : base_price
  end
end

# Efficient queries with includes
def marketplace_apps
  App.published
     .includes(:creator_profile, :app_reviews, cover_image_attachment: :blob)
     .page(params[:page])
end
```

### Testing Approach
```ruby
# Test files mirror app structure
# test/models/app_test.rb
class AppTest < ActiveSupport::TestCase
  test "generates slug from name" do
    app = create(:app, name: "My Cool App")
    assert_equal "my-cool-app", app.slug
  end
end

# Use factories for test data
FactoryBot.define do
  factory :app do
    team
    creator_profile
    name { "Test App" }
    prompt { "Create a todo list app" }
    base_price { 9.99 }
  end
end
```

## 🚀 Common Tasks

### Creating a New Model
```bash
# Use BulletTrain's super scaffolding
rails generate super_scaffold ModelName Team \
  field1:type{options} \
  field2:type{options}

# Example:
rails generate super_scaffold Product Team \
  name:text_field{required} \
  price:number_field{required} \
  status:options{draft,published,archived}
```

### Adding API Endpoints
```ruby
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :apps do
      member do
        post :generate
        post :publish
        get :analytics
      end
      
      collection do
        get :trending
      end
    end
  end
end
```

### Background Job Pattern
```ruby
class AppGenerationJob < ApplicationJob
  queue_as :ai_generation
  
  def perform(app)
    # Long-running AI task
    result = AI::AppGeneratorService.new(app.team).generate(app.prompt)
    
    if result[:success]
      app.update!(status: 'generated', files: result[:files])
      AppDeploymentJob.perform_later(app)
    else
      app.update!(status: 'failed', error: result[:error])
    end
  end
end
```

## 🎨 UI/UX Patterns

### Hotwire Conventions
```erb
<!-- Turbo Frame for partial updates -->
<%= turbo_frame_tag "app_#{@app.id}" do %>
  <div class="app-card">
    <!-- Content that updates -->
  </div>
<% end %>

<!-- Stimulus for interactivity -->
<div data-controller="app-preview"
     data-app-preview-url-value="<%= @app.preview_url %>">
  <button data-action="app-preview#refresh">Refresh</button>
</div>
```

### Tailwind Classes
```erb
<!-- Standard card component -->
<div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
  <h3 class="text-lg font-semibold text-gray-900 mb-2">
    <%= @app.name %>
  </h3>
  <p class="text-gray-600">
    <%= @app.description %>
  </p>
</div>

<!-- Primary button -->
<%= link_to "Generate App", 
    new_account_app_path,
    class: "btn btn-primary" %>
```

## 🔐 Security Considerations

### Input Validation
- Sanitize all user inputs
- Validate AI prompts for malicious content
- Scan generated code before deployment
- Use strong parameters in controllers

### AI Safety
```ruby
class AI::PromptValidator
  BLOCKED_PATTERNS = [
    /malware|virus|hack/i,
    /\beval\b|\bexec\b/,
    /password|credential/i
  ]
  
  def self.safe?(prompt)
    BLOCKED_PATTERNS.none? { |pattern| prompt.match?(pattern) }
  end
end
```

### Multi-tenancy
- All queries scoped to current_team
- Use BulletTrain's authorize_resource
- Implement row-level security in Supabase
- Separate concerns with service objects

## 📊 Performance Optimization

### Database
- Add indexes for foreign keys and lookups
- Use counter caches for associations
- Implement Russian doll caching
- Optimize N+1 queries with includes

### Caching Strategy
```ruby
# Model caching
class App < ApplicationRecord
  def cache_key_with_version
    "#{super}-#{purchases_count}-#{updated_at.to_i}"
  end
end

# View caching
<% cache [@app, current_user] do %>
  <%= render 'app_details', app: @app %>
<% end %>

# Redis caching for expensive operations
Rails.cache.fetch("trending_apps", expires_in: 1.hour) do
  App.trending.limit(10).to_a
end
```

### Background Jobs
- Use Sidekiq for all async work
- Implement idempotent jobs
- Add retry logic with exponential backoff
- Monitor job queues and performance

## 🔄 Deployment Pipeline

### Development
```bash
# Start all services
bin/dev

# Run tests
bin/rails test

# Run linting
bin/standardrb
```

### Staging
- Auto-deploy from `develop` branch
- Run full test suite
- Preview deployments for PRs

### Production
- Deploy from `main` branch only
- Run migrations in release phase
- Zero-downtime deployments
- Automatic rollback on failure

## 💡 Best Practices

### API Design
- Version all APIs (v1, v2, etc.)
- Use consistent response formats
- Implement rate limiting
- Return appropriate HTTP status codes

### Error Handling
```ruby
class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: 'Not found' }, status: :not_found
  end
  
  rescue_from AI::GenerationError do |e|
    logger.error "AI Generation failed: #{e.message}"
    render json: { error: 'Generation failed. Please try again.' }, 
           status: :unprocessable_entity
  end
end
```

### Monitoring
- Track AI costs per user/team
- Monitor generation success rates
- Alert on high error rates
- Track performance metrics

## 🤝 Collaboration

### Git Workflow
- Feature branches from `develop`
- PR reviews required
- Squash and merge to keep history clean
- Tag releases with semantic versioning

### Documentation
- Update docs with significant changes
- Add inline comments for complex logic
- Keep README current
- Document API changes

## 🚦 Quick Reference

### Environment Variables
```bash
# Required for development
OPENROUTER_API_KEY=         # AI API access
STRIPE_API_KEY=             # Payment processing
CLOUDFLARE_API_KEY=         # App hosting
SUPABASE_URL=               # Database URL
SUPABASE_KEY=               # Database key
REDIS_URL=                  # Background jobs
```

### Common Commands
```bash
# Generate new model with UI
rails g super_scaffold ModelName Team field:type

# Run specific tests
bin/rails test path/to/test.rb

# Open Rails console
bin/rails console

# Run background jobs
bundle exec sidekiq

# Deploy to production
git push production main
```

### Debugging
```ruby
# Add breakpoints
binding.pry  # Requires pry-rails gem

# Rails console helpers
app.account_apps_path  # Test routes
app.get '/apps'        # Make requests

# Inspect queries
App.published.to_sql   # See generated SQL
App.published.explain  # Query plan
```

---

Remember: Keep it simple, ship fast, and let AI do the heavy lifting! 🚀
