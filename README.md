# OverSkill - AI-Powered App Marketplace Platform

> Transform ideas into income-generating apps in minutes using AI, with built-in marketplace and viral growth mechanics.

[![Built with Bullet Train](https://img.shields.io/badge/Built%20with-Bullet%20Train-purple)](https://bullettrain.co)
[![Ruby](https://img.shields.io/badge/Ruby-3.2.0-red)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/Rails-7.1.0-red)](https://rubyonrails.org)

## 🚀 Overview

OverSkill is the ultimate "make money online" platform that enables anyone to create, deploy, and monetize AI-generated applications without coding knowledge. Built on Bullet Train Pro, it combines:

- **AI-Powered App Generation** - Using Kimi K2 via OpenRouter for best-in-class code generation
- **Instant Deployment** - Static hosting via Cloudflare Workers + R2
- **Built-in Marketplace** - Connect creators with buyers automatically
- **Viral Growth Engine** - Network effects and referral systems built-in
- **Complete Monetization** - Stripe Connect for instant payouts

## 📚 Documentation

- [Business Plan](docs/business-plan.md) - Complete business strategy and market analysis
- [Architecture](docs/architecture.md) - Technical architecture and infrastructure design
- [Scaffolding Plan](docs/scaffolding.md) - BulletTrain super-scaffolding implementation
- [AI Context](docs/ai-context.md) - Shared context for Claude/Cursor/Kimi K2 development
- [API Documentation](docs/api.md) - Platform and generated app APIs
- [Deployment Guide](docs/deployment.md) - Production deployment instructions

## 🏗️ Quick Start

### Prerequisites
- Ruby 3.3.0 (Note: Ruby 3.4.4 has SSL issues with RubyGems)
- PostgreSQL 14+
- Redis 7+
- Node.js 18+
- Yarn

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/overskill.git
cd overskill

# Run BulletTrain configuration
bin/configure

# Install dependencies and setup database
bin/setup

# Environment Setup
# 1. Shared development config (already in repo)
#    .env.development contains non-sensitive defaults
#
# 2. Create your personal secrets file:
cp .env.development.local .env.development.local
# Edit .env.development.local with your API keys
# (See detailed instructions in the file)

# Start the application
bin/dev
```

Visit `http://localhost:3000` to see OverSkill running locally.

## 🎯 Core Features

### For Creators
- **AI App Builder** - Describe your app idea in plain language
- **Instant Preview** - See your app running in seconds
- **One-Click Publishing** - Deploy to production instantly
- **Built-in Analytics** - Track users, revenue, and engagement
- **Revenue Dashboard** - Real-time earnings and payouts

### For Users
- **App Marketplace** - Discover and purchase AI-generated apps
- **Try Before Buy** - Preview apps before purchasing
- **Instant Access** - Start using apps immediately
- **Custom Domains** - Professional URLs for your apps
- **Team Collaboration** - Share apps with your team

### Platform Features
- **Viral Mechanics** - Referral system and "Powered by" badges
- **AI Cost Optimization** - Smart routing between AI providers
- **Global CDN** - Fast loading worldwide via Cloudflare
- **Multi-tenant Security** - Isolated data per app via Supabase RLS
- **Automated Testing** - AI-generated tests for each app

## 📁 Project Structure

```
overskill/
├── app/
│   ├── controllers/
│   │   ├── apps_controller.rb          # App management
│   │   ├── marketplace_controller.rb   # Marketplace browsing
│   │   └── ai_generations_controller.rb # AI generation endpoints
│   ├── models/
│   │   ├── app.rb                     # Core app model
│   │   ├── app_generation.rb          # AI generation tracking
│   │   └── creator_profile.rb         # Creator profiles
│   ├── services/
│   │   ├── ai/                        # AI integration services
│   │   ├── deployment/                # App deployment logic
│   │   └── marketplace/               # Marketplace mechanics
│   └── views/
├── docs/                              # Documentation
├── lib/
│   └── generators/                    # Custom generators
└── test/                             # Test suite
```

## 🧪 Testing

```bash
# Run all tests
bin/rails test

# Run specific test file
bin/rails test test/models/app_test.rb

# Run system tests
bin/rails test:system
```

## 🚀 Deployment

OverSkill is designed to run on modern cloud platforms. See our [Deployment Guide](docs/deployment.md) for detailed instructions.

### Quick Deploy Options

#### Render (Recommended)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/yourusername/overskill)

#### Railway
[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/new/template?template=https://github.com/yourusername/overskill)

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Built on [Bullet Train](https://bullettrain.co) - The Ruby on Rails SaaS Framework
- Powered by [Kimi K2](https://kimi.ai) via [OpenRouter](https://openrouter.ai)
- Infrastructure by [Cloudflare](https://cloudflare.com) and [Supabase](https://supabase.com)

## 📞 Support

- Documentation: [docs.overskill.app](https://docs.overskill.app)
- Discord: [Join our community](https://discord.gg/overskill)
- Email: support@overskill.app

---

**Ready to turn your ideas into income?** Start building with OverSkill today! 🚀
