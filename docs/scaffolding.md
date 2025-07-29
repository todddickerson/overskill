# OverSkill BulletTrain Super-Scaffolding Plan

> This document outlines all models, relationships, and scaffolding commands for the OverSkill platform using BulletTrain's super-scaffolding system.

## 🏗️ Scaffolding Overview

BulletTrain's super-scaffolding allows us to generate complete CRUD interfaces, API endpoints, and views with a single command. This document serves as our blueprint for all models and their relationships.

### Key Syntax Notes:
- Parent model is always `Team` for multi-tenancy (can add `,User` for user association)
- Field options: `{required}`, `{readonly}`, `{default=value}`, `{minimum=n}`, `{maximum=n}`
- References: `{class_name=Model,required}`
- Options field: `field:options{option1,option2,option3}`
- Unique validation must be added manually to models (not a field option)

### BulletTrain Super-Scaffolding Lessons Learned:
1. **Quote complex field options**: Use quotes for fields with multiple options like `"level:number_field{required,default=1}"`
2. **Vanilla option for non-FK fields**: Fields ending in `_id` need `{vanilla}` if they're not foreign keys (e.g., `stripe_account_id:text_field{vanilla}`)
3. **Skip navbar prompt**: Use `--skip-navbar` to avoid interactive prompts during scaffolding
4. **Membership reference**: The scaffolding needs manual updates to add membership reference after generation
5. **Unique indexes**: Don't add unique index on fields that already have indexes from `references`

### BulletTrain Membership Pattern:
- Use `Membership` (not `User`) for data that should persist after user deletion
- `Membership` represents the User-Team relationship
- Pattern: `Team,Membership` for membership-scoped data
- Pattern: `Team,User` for user-specific data that can be deleted
- Example: Apps should belong to Membership so they persist if creator leaves

## 📊 Core Models & Scaffolding Commands

### Phase 1: User & Creator System

#### 1. CreatorProfile
Extends the Membership model with creator-specific features. Using Membership ensures creator data persists even if user account is deleted.

```bash
# One-to-one with Membership (data persists after user deletion)
rails generate super_scaffold CreatorProfile Team,Membership \
  username:text_field{required} \
  bio:text_area \
  level:number_field{required,default=1} \
  total_earnings:number_field{readonly,default=0} \
  total_sales:number_field{readonly,default=0} \
  verification_status:options{unverified,pending,verified} \
  featured_until:date_and_time_field \
  slug:text_field{required} \
  stripe_account_id:text_field \
  public_email:email_field \
  website_url:text_field \
  twitter_handle:text_field \
  github_username:text_field
```

#### 2. Follow System
For creator following functionality.

```bash
rails generate super_scaffold Follow Team,User \
  follower:references{class_name=User,required} \
  followed:references{class_name=User,required}

# Note: We'll need to manually update the association to CreatorProfile
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
  slug:text_field{required} \
  description:text_area \
  creator:references{class_name=Membership,required} \
  prompt:text_area{required} \
  app_type:options{tool,saas,landing_page,dashboard,game,other} \
  framework:options{react,vue,nextjs,vanilla} \
  status:options{generating,generated,testing,ready,published,failed} \
  visibility:options{private,preview,public} \
  base_price:number_field{required,default=0} \
  stripe_product_id:text_field \
  preview_url:text_field \
  production_url:text_field \
  github_repo:text_field \
  total_users:number_field{readonly,default=0} \
  total_revenue:number_field{readonly,default=0} \
  rating:number_field{readonly,default=0} \
  featured:boolean{default=false} \
  featured_until:date_and_time_field \
  launch_date:date_and_time_field \
  ai_model:text_field{readonly} \
  ai_cost:number_field{readonly,default=0}
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
Version control for apps with GitHub integration.

```bash
rails generate super_scaffold AppVersion Team \
  app:references{required} \
  user:references \
  commit_sha:text_field \
  commit_message:text_field \
  version_number:text_field{required} \
  changelog:text_area \
  files_snapshot:text_area \
  changed_files:text_area \
  external_commit:boolean{default=false} \
  deployed:boolean{default=false} \
  published_at:date_and_time_field
```

#### 7. AppCollaborator
Manages GitHub repository collaborators.

```bash
rails generate super_scaffold AppCollaborator Team \
  app:references{required} \
  membership:references{required} \
  role:options{viewer,contributor,admin} \
  github_username:text_field \
  permissions_synced:boolean{default=false}
```

### Phase 3: Marketplace & Commerce

#### 8. Purchase
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

#### 9. AppReview
User reviews for apps. Uses Membership so reviews persist.

```bash
rails generate super_scaffold AppReview Team \
  app:references{required} \
  membership:references{required} \
  rating:number_field{required,minimum=1,maximum=5} \
  title:text_field \
  content:text_area \
  verified_purchase:boolean{required} \
  helpful_count:number_field{default=0} \
  reported:boolean{default=false}
```

#### 10. FlashSale
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

#### 11. ReferralCode
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

#### 12. Achievement
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

#### 13. MembershipAchievement
Tracks earned achievements. Uses Membership so achievements persist.

```bash
rails generate super_scaffold MembershipAchievement Team,Membership \
  achievement:references{required} \
  earned_at:date_and_time_field{required} \
  progress:number_field{default=0}
```

### Phase 5: Analytics & Monitoring

#### 14. AppAnalytic
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

#### 15. AIUsageLog
Tracks AI API usage for billing. Uses Membership to preserve usage history.

```bash
rails generate super_scaffold AIUsageLog Team,Membership \
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

#### 16. Post
Community posts/updates. Uses Membership so content persists.

```bash
rails generate super_scaffold Post Team \
  membership:references{required} \
  app:references \
  title:text_field \
  content:text_area{required} \
  post_type:options{announcement,tutorial,showcase,question} \
  pinned:boolean{default=false} \
  likes_count:number_field{default=0} \
  comments_count:number_field{default=0} \
  published_at:date_and_time_field
```

#### 17. Comment
Comments on posts. Uses Membership so comments persist.

```bash
rails generate super_scaffold Comment Team \
  post:references{required} \
  membership:references{required} \
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
  
  # OverSkill associations (user-specific, deletable)
  has_many :purchases
  has_one :referral_code
  
  # Following (through memberships)
  has_many :active_follows, through: :memberships
end
```

### app/models/membership.rb
```ruby
class Membership < ApplicationRecord
  # BulletTrain associations...
  
  # OverSkill associations (persist after user deletion)
  has_one :creator_profile, dependent: :destroy
  has_many :apps, foreign_key: :creator_id
  has_many :app_reviews
  has_many :posts
  has_many :comments
  has_many :membership_achievements
  has_many :achievements, through: :membership_achievements
  has_many :ai_usage_logs
  has_many :app_collaborators
  
  # Following
  has_many :active_follows, class_name: "Follow", foreign_key: "follower_id"
  has_many :following, through: :active_follows, source: :followed
end
```

### app/models/creator_profile.rb
```ruby
class CreatorProfile < ApplicationRecord
  belongs_to :membership
  belongs_to :team
  
  has_many :apps, through: :membership
  has_many :posts, through: :membership
  has_many :passive_follows, class_name: "Follow", foreign_key: "followed_id"
  has_many :followers, through: :passive_follows, source: :follower
  
  # Validations (add unique constraints manually)
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
  belongs_to :creator, class_name: 'Membership'
  
  has_many :app_generations
  has_many :app_files
  has_many :app_versions
  has_many :app_collaborators
  has_many :purchases
  has_many :app_reviews
  has_many :flash_sales
  has_many :app_analytics
  has_many :posts
  
  # Scopes
  scope :published, -> { where(status: 'published', visibility: 'public') }
  scope :featured, -> { where(featured: true).where('featured_until > ?', Time.current) }
  
  # Validations (add unique constraints manually)
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
   - AppVersion (GitHub integration)
   - AppCollaborator (GitHub integration)

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

## ⚠️ Manual Post-Scaffolding Updates

After running the scaffolding commands, you'll need to make these manual updates:

1. **Add unique constraints in migrations**
   ```ruby
   add_index :creator_profiles, :username, unique: true
   add_index :creator_profiles, :slug, unique: true
   add_index :apps, :slug, unique: true
   ```

2. **Update associations for Membership pattern**
   - Update generated associations to use `class_name: 'Membership'` where needed
   - Change foreign keys from `user_id` to `membership_id` in migrations
   - Update `Follow` model to reference `CreatorProfile` for followed
   - Ensure `creator` association in App model uses `class_name: 'Membership'`

3. **Add custom validations**
   - Unique validations for slugs, usernames
   - Custom validation logic for business rules
   - Add team scope validations where needed

4. **Configure references**
   - Update foreign key constraints
   - Add dependent: :destroy where appropriate
   - Ensure proper cascading for membership deletion

5. **Helper methods for User access**
   ```ruby
   # In models using Membership, add helper to get user
   delegate :user, to: :membership
   
   # In controllers, helper to get membership from current_user
   def current_membership
     current_user.memberships.find_by(team: current_team)
   end
   ```
