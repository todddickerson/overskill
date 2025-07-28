# OverSkill BulletTrain Super-Scaffolding Plan

> This document outlines all models, relationships, and scaffolding commands for the OverSkill platform using BulletTrain's super-scaffolding system.

## 🏗️ Scaffolding Overview

BulletTrain's super-scaffolding allows us to generate complete CRUD interfaces, API endpoints, and views with a single command. This document serves as our blueprint for all models and their relationships.

## 📊 Core Models & Scaffolding Commands

### Phase 1: User & Creator System

#### 1. CreatorProfile
Extends the User model with creator-specific features.

```bash
# One-to-one with User (belongs_to)
rails generate super_scaffold CreatorProfile User,Team \
  username:text_field{required,unique} \
  bio:text_area \
  level:number_field{required} \
  total_earnings:number_field{readonly} \
  total_sales:number_field{readonly} \
  verification_status:options{unverified,pending,verified} \
  featured_until:date_and_time_field \
  slug:text_field{required,unique} \
  stripe_account_id:text_field \
  public_email:email_field \
  website_url:text_field \
  twitter_handle:text_field \
  github_username:text_field
```

#### 2. Follow System
For creator following functionality.

```bash
rails generate super_scaffold Follow User,Team \
  follower:references{class_name=User,required} \
  followed:references{class_name=CreatorProfile,required} \
  created_at:date_and_time_field{readonly}

# Add indexes in migration
# add_index :follows, [:follower_id, :followed_id], unique: true
# add_index :follows, :followed_id
```

### Phase 2: App Generation & Management

#### 3. App Model
Core model for generated applications.

```bash
rails generate super_scaffold App Team \
  name:text_field{required} \
  slug:text_field{required,unique} \
  description:text_area \
  creator_profile:references{required} \
  prompt:text_area{required} \
  app_type:options{tool,saas,landing_page,dashboard,game,other} \
  framework:options{react,vue,nextjs,vanilla} \
  status:options{generating,generated,testing,ready,published,failed} \
  visibility:options{private,preview,public} \
  base_price:number_field{required} \
  stripe_product_id:text_field \
  preview_url:text_field \
  production_url:text_field \
  github_repo:text_field \
  total_users:number_field{readonly} \
  total_revenue:number_field{readonly} \
  rating:number_field{readonly} \
  featured:boolean \
  featured_until:date_and_time_field \
  launch_date:date_and_time_field \
  ai_model:text_field{readonly} \
  ai_cost:number_field{readonly}
```

#### 4. AppGeneration
Tracks AI generation requests and results.

```bash
rails generate super_scaffold AppGeneration Team \
  app:references{required} \
  prompt:text_area{required} \
  enhanced_prompt:text_area{readonly} \
  status:options{processing,completed,failed} \
  ai_model:options{kimi-k2,deepseek-v3,claude-sonnet,gpt-4} \
  started_at:date_and_time_field{required} \
  completed_at:date_and_time_field \
  duration_seconds:number_field \
  input_tokens:number_field \
  output_tokens:number_field \
  total_cost:number_field \
  error_message:text_area \
  retry_count:number_field{default=0}
```

#### 5. AppFile
Stores generated application files.

```bash
rails generate super_scaffold AppFile Team \
  app:references{required} \
  path:text_field{required} \
  content:text_area{required} \
  file_type:options{html,css,js,jsx,json,md,yaml,env} \
  size_bytes:number_field{readonly} \
  checksum:text_field{readonly} \
  is_entry_point:boolean
```

#### 6. AppVersion
Version control for apps (future feature).

```bash
rails generate super_scaffold AppVersion Team \
  app:references{required} \
  version_number:text_field{required} \
  changelog:text_area \
  files_snapshot:text_area \
  published_at:date_and_time_field \
  is_current:boolean
```

### Phase 3: Marketplace & Commerce

#### 7. Purchase
Tracks app purchases.

```bash
rails generate super_scaffold Purchase Team \
  user:references{required} \
  app:references{required} \
  stripe_payment_intent_id:text_field{required,unique} \
  amount:number_field{required} \
  platform_fee:number_field{required} \
  creator_revenue:number_field{required} \
  status:options{pending,completed,refunded,disputed} \
  purchased_at:date_and_time_field{required} \
  refunded_at:date_and_time_field \
  referral_code:references \
  referral_commission:number_field
```

#### 8. AppReview
User reviews for apps.

```bash
rails generate super_scaffold AppReview Team \
  app:references{required} \
  user:references{required} \
  rating:number_field{required,minimum=1,maximum=5} \
  title:text_field \
  content:text_area \
  verified_purchase:boolean{required} \
  helpful_count:number_field{default=0} \
  reported:boolean{default=false}
```

#### 9. FlashSale
Time-limited sales for apps.

```bash
rails generate super_scaffold FlashSale Team \
  app:references{required} \
  discount_percentage:number_field{required,minimum=10,maximum=90} \
  starts_at:date_and_time_field{required} \
  ends_at:date_and_time_field{required} \
  max_uses:number_field \
  uses_count:number_field{default=0} \
  is_active:boolean{required}
```

### Phase 4: Viral Growth & Gamification

#### 10. ReferralCode
User referral tracking.

```bash
rails generate super_scaffold ReferralCode User,Team \
  code:text_field{required,unique} \
  clicks:number_field{default=0} \
  signups:number_field{default=0} \
  conversions:number_field{default=0} \
  total_earned:number_field{default=0} \
  is_active:boolean{default=true}
```

#### 11. Achievement
Gamification achievements.

```bash
rails generate super_scaffold Achievement Team \
  name:text_field{required} \
  description:text_area \
  icon:text_field \
  points:number_field{required} \
  requirement_type:options{apps_created,sales_made,users_acquired,revenue_earned} \
  requirement_value:number_field{required} \
  badge_color:color_picker
```

#### 12. UserAchievement
Tracks earned achievements.

```bash
rails generate super_scaffold UserAchievement User,Team \
  achievement:references{required} \
  earned_at:date_and_time_field{required} \
  progress:number_field{default=0}
```

### Phase 5: Analytics & Monitoring

#### 13. AppAnalytic
Daily analytics for apps.

```bash
rails generate super_scaffold AppAnalytic Team \
  app:references{required} \
  date:date_field{required} \
  views:number_field{default=0} \
  unique_visitors:number_field{default=0} \
  signups:number_field{default=0} \
  purchases:number_field{default=0} \
  revenue:number_field{default=0} \
  average_session_duration:number_field
```

#### 14. AIUsageLog
Tracks AI API usage for billing.

```bash
rails generate super_scaffold AIUsageLog User,Team \
  model:options{kimi-k2,deepseek-v3,claude-sonnet,gpt-4} \
  action:options{generate_app,enhance_prompt,generate_test,analyze_code} \
  input_tokens:number_field{required} \
  output_tokens:number_field{required} \
  total_tokens:number_field{required} \
  input_cost:number_field{required} \
  output_cost:number_field{required} \
  total_cost:number_field{required} \
  success:boolean{required} \
  duration_ms:number_field
```

### Phase 6: Community Features

#### 15. Post
Community posts/updates.

```bash
rails generate super_scaffold Post Team \
  creator_profile:references{required} \
  app:references \
  title:text_field \
  content:text_area{required} \
  post_type:options{announcement,tutorial,showcase,question} \
  pinned:boolean{default=false} \
  likes_count:number_field{default=0} \
  comments_count:number_field{default=0} \
  published_at:date_and_time_field
```

#### 16. Comment
Comments on posts.

```bash
rails generate super_scaffold Comment Team \
  post:references{required} \
  user:references{required} \
  parent:references{class_name=Comment} \
  content:text_area{required} \
  likes_count:number_field{default=0} \
  reported:boolean{default=false}
```

## 🔗 Model Associations

After scaffolding, add these associations to the models:

### app/models/user.rb
```ruby
class User < ApplicationRecord
  # BulletTrain associations...
  
  # OverSkill associations
  has_one :creator_profile, dependent: :destroy
  has_many :apps, through: :teams
  has_many :purchases
  has_many :app_reviews
  has_many :posts, through: :creator_profile
  has_many :comments
  has_one :referral_code
  has_many :user_achievements
  has_many :achievements, through: :user_achievements
  
  # Following
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id"
  has_many :following, through: :active_follows, source: :followed
end
```

### app/models/creator_profile.rb
```ruby
class CreatorProfile < ApplicationRecord
  belongs_to :user
  belongs_to :team
  
  has_many :apps
  has_many :posts
  has_many :passive_follows, class_name: "Follow", foreign_key: "followed_id"
  has_many :followers, through: :passive_follows, source: :follower
  
  # Validations
  validates :username, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  
  # Callbacks
  before_validation :generate_slug
  
  private
  
  def generate_slug
    self.slug ||= username&.parameterize
  end
end
```

### app/models/app.rb
```ruby
class App < ApplicationRecord
  belongs_to :team
  belongs_to :creator_profile
  
  has_many :app_generations
  has_many :app_files
  has_many :app_versions
  has_many :purchases
  has_many :app_reviews
  has_many :flash_sales
  has_many :app_analytics
  has_many :posts
  
  # Scopes
  scope :published, -> { where(status: 'published', visibility: 'public') }
  scope :featured, -> { where(featured: true).where('featured_until > ?', Time.current) }
  
  # Validations
  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :base_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  
  # Callbacks
  before_validation :generate_slug
  after_create :create_initial_generation
  
  private
  
  def generate_slug
    self.slug ||= name&.parameterize
  end
  
  def create_initial_generation
    app_generations.create!(
      prompt: prompt,
      status: 'processing',
      ai_model: 'kimi-k2',
      started_at: Time.current
    )
  end
end
```

## 🎯 Scaffolding Execution Order

1. **Phase 1**: User & Creator System
   - CreatorProfile
   - Follow

2. **Phase 2**: App Generation (Core MVP)
   - App
   - AppGeneration
   - AppFile

3. **Phase 3**: Marketplace (Revenue)
   - Purchase
   - AppReview
   - FlashSale

4. **Phase 4**: Growth Features
   - ReferralCode
   - Achievement
   - UserAchievement

5. **Phase 5**: Analytics
   - AppAnalytic
   - AIUsageLog

6. **Phase 6**: Community
   - Post
   - Comment
   - AppVersion (later)

## 🚀 Post-Scaffolding Tasks

After running all scaffolding commands:

1. **Run migrations**
   ```bash
   rails db:migrate
   ```

2. **Add custom validations and callbacks**

3. **Configure API endpoints**
   ```bash
   # config/routes.rb
   namespace :api do
     namespace :v1 do
       resources :apps do
         member do
           post :generate
           post :publish
           get :preview
         end
       end
     end
   end
   ```

4. **Add service objects**
   - `app/services/ai/app_generator_service.rb`
   - `app/services/deployment/cloudflare_deployer.rb`
   - `app/services/marketplace/pricing_engine.rb`

5. **Configure background jobs**
   - `app/jobs/app_generation_job.rb`
   - `app/jobs/app_deployment_job.rb`
   - `app/jobs/analytics_aggregation_job.rb`

## 📝 Notes

- All models include `Team` for multi-tenancy (BulletTrain pattern)
- Soft deletes are handled by BulletTrain's `discarded` gem
- API versioning follows BulletTrain conventions
- Use `super_scaffold:crud` for additional customization after initial generation
