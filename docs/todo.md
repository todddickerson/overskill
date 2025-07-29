# OverSkill TODO Tracking

This document tracks all pending features and improvements for the OverSkill platform.

## Phase 2B: AI App Generation (Complete!)
- [x] Set up OpenRouter API integration with Kimi K2
- [x] Create AI::OpenRouterClient service
- [x] Create AI::AppGeneratorService orchestrator
- [x] Create AppGenerationJob background job
- [x] Implement Turbo status updates
- [x] Create basic generation UI
- [x] Add generation status tracking
- [x] Implement prompt template system (like lovable.dev)
- [x] Create prompt templates for todo, game, landing, dashboard
- [x] Add intelligent template selection based on prompts

## Phase 2C: Testing & Enhancement
- [ ] Test full app generation with various prompts
- [ ] Add more prompt templates:
  - [ ] Calculator app template
  - [ ] Timer/countdown template
  - [ ] Blog/content site template
  - [ ] Chat app template
- [ ] Implement app preview in iframe
- [ ] Add one-click deployment to Cloudflare
- [ ] Create AI::SecurityScanner service
- [ ] Add generation analytics and metrics

## Phase 3: Marketplace & Commerce
- [ ] Scaffold Purchase model
- [ ] Scaffold AppReview model
- [ ] Scaffold FlashSale model
- [ ] Implement Stripe Connect for creators
- [ ] Build marketplace browsing UI
- [ ] Add search and filtering
- [ ] Implement purchase flow
- [ ] Add review system

## Phase 4: Deployment & Hosting
- [ ] Integrate Cloudflare Workers API
- [ ] Set up R2 storage for static files
- [ ] Create deployment pipeline
- [ ] Add custom domain support
- [ ] Implement SSL certificates
- [ ] Add usage analytics

## Phase 5: Creator Tools
- [ ] Creator dashboard
- [ ] Revenue analytics
- [ ] App version management
- [ ] Collaboration features
- [ ] GitHub integration
- [ ] Export functionality

## Phase 6: Advanced Features
- [ ] AI model selection (DeepSeek v3, Claude)
- [ ] Template library
- [ ] Component marketplace
- [ ] Team collaboration
- [ ] White-label options
- [ ] API access for generated apps

## Technical Debt & Improvements
- [ ] Add comprehensive test coverage
- [ ] Implement caching strategy
- [ ] Optimize database queries
- [ ] Add error tracking (Sentry)
- [ ] Implement rate limiting
- [ ] Add API documentation
- [ ] Create admin dashboard

## Security & Compliance
- [ ] Implement code sandboxing
- [ ] Add malware scanning
- [ ] PCI compliance for payments
- [ ] GDPR compliance features
- [ ] Terms of service acceptance
- [ ] Content moderation system