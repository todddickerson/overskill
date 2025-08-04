# OAuth & API Integrations Guide for OverSkill

**CRITICAL DOCUMENTATION** - This system provides secure backend integrations for generated apps via Cloudflare Workers.

## Overview

OverSkill's OAuth and API integration system enables generated apps to securely connect to third-party services without exposing API keys or secrets to the client. This addresses a major competitive gap identified in Lovable, Base44, and other AI code generators.

## Architecture

### Components Overview
```
Generated App (Client-Side React)
           ↓ HTTPS Request
Cloudflare Worker (Proxy Layer) 
           ↓ Authenticated Request
Third-Party API (Google, Stripe, etc.)
```

### Security Model
- **No Client-Side Secrets**: API keys stored securely in Cloudflare Worker environment
- **CORS Protection**: Workers only accept requests from the app's domain
- **Encrypted Storage**: All secrets encrypted in Rails database
- **Proxy Pattern**: Workers act as secure intermediaries

## OAuth Integration System

### Supported Providers
1. **Google OAuth 2.0**: OpenID Connect with profile/email access
2. **GitHub OAuth**: User authentication and API access
3. **Auth0**: Enterprise identity management

### Database Schema

#### AppOAuthProvider Model
```ruby
# app/models/app_oauth_provider.rb
class AppOAuthProvider < ApplicationRecord
  belongs_to :app
  
  SUPPORTED_PROVIDERS = %w[google github auth0].freeze
  
  validates :provider, presence: true, inclusion: { in: SUPPORTED_PROVIDERS }
  validates :client_id, presence: true
  validates :client_secret, presence: true  # Encrypted
  validates :redirect_uri, presence: true
  validates :provider, uniqueness: { scope: :app_id }
  
  encrypts :client_secret
end
```

#### Key Methods
- `worker_env_vars`: Returns environment variables for Cloudflare Worker
- `generate_worker_code`: Generates OAuth-specific Worker JavaScript
- `default_scopes`: Provider-specific default OAuth scopes

### OAuth Flow Implementation

#### 1. Google OAuth Worker
```javascript
// Generated Worker handles:
export default {
  async fetch(request, env, ctx) {
    // 1. /auth/google - Redirect to Google OAuth
    // 2. /auth/google/callback - Exchange code for tokens
    // 3. /auth/google/refresh - Refresh expired tokens
  }
};
```

#### 2. Client-Side Integration
```javascript
// In generated React app:
const handleGoogleLogin = async () => {
  // Redirect to Worker OAuth endpoint
  window.location.href = 'https://api-worker.app123.workers.dev/auth/google';
};

// Handle callback with tokens
const tokens = await response.json();
// Store tokens securely (HttpOnly cookies recommended)
```

## API Integration System

### Supported Integration Types
- **Bearer Token**: Authorization: Bearer {token}
- **API Key**: X-API-Key header or custom header
- **Basic Auth**: Base64 encoded credentials
- **Custom Auth**: Flexible authentication patterns
- **No Auth**: Public APIs

### Database Schema

#### AppApiIntegration Model
```ruby
# app/models/app_api_integration.rb
class AppApiIntegration < ApplicationRecord
  belongs_to :app
  
  AUTH_TYPES = %w[bearer api_key basic custom none].freeze
  
  validates :name, presence: true, uniqueness: { scope: :app_id }
  validates :base_url, presence: true
  validates :auth_type, inclusion: { in: AUTH_TYPES }
  validates :path_prefix, presence: true
  validates :api_key, presence: true, if: auth_required?
  
  encrypts :api_key
end
```

### Common API Integrations

#### Pre-configured Services
```ruby
AppApiIntegration.preset_configs
# Returns configurations for:
# - Stripe (payments)
# - SendGrid (email)
# - Twilio (SMS)
# - OpenAI (AI)
# - Airtable (data)
```

### API Proxy Worker Implementation

#### Generated Worker Structure
```javascript
// API Proxy Worker for App: MyApp
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    
    // Route to appropriate API handler
    if (url.pathname.startsWith('/stripe')) {
      return await proxyToStripe(request, env, url);
    }
    if (url.pathname.startsWith('/sendgrid')) {
      return await proxyToSendgrid(request, env, url);
    }
    // ... more integrations
  }
};

async function proxyToStripe(request, env, url) {
  // Remove proxy prefix: /stripe/customers -> /customers
  const targetPath = url.pathname.replace('/stripe', '');
  const targetUrl = 'https://api.stripe.com/v1' + targetPath + url.search;
  
  // Add authentication
  const headers = new Headers();
  headers.set('Authorization', `Bearer ${env.STRIPE_API_KEY}`);
  
  // Forward request with authentication
  const response = await fetch(targetUrl, {
    method: request.method,
    headers: headers,
    body: request.method !== 'GET' ? await request.blob() : null
  });
  
  return response;
}
```

## Code Generation System

### Cloudflare::WorkerGeneratorService
```ruby
# app/services/cloudflare/worker_generator_service.rb
class Cloudflare::WorkerGeneratorService
  def initialize(app)
    @app = app
  end
  
  def generate_oauth_worker(provider:, redirect_uri:)
    # Generates provider-specific OAuth Worker
  end
  
  def generate_api_proxy_worker(api_config)
    # Generates API proxy Worker from ERB template
  end
end
```

### Template System
- **OAuth Templates**: Provider-specific authentication flows
- **API Proxy Template**: Generic proxy with ERB interpolation
- **Environment Variables**: Secure secret injection

## Client-Side Usage Patterns

### OAuth Authentication
```javascript
// React component for Google OAuth
const GoogleLoginButton = () => {
  const handleLogin = () => {
    // Redirect to Worker OAuth endpoint
    window.location.href = `${WORKER_URL}/auth/google`;
  };
  
  return (
    <button onClick={handleLogin} className="oauth-button">
      <i className="fab fa-google"></i>Sign in with Google
    </button>
  );
};
```

### API Calls via Proxy
```javascript
// Stripe payment processing
const createPayment = async (amount, currency) => {
  const response = await fetch(`${WORKER_URL}/stripe/payment_intents`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      amount: amount * 100, // Stripe expects cents
      currency: currency,
      automatic_payment_methods: { enabled: true }
    })
  });
  
  return response.json();
};

// SendGrid email sending
const sendEmail = async (to, subject, content) => {
  const response = await fetch(`${WORKER_URL}/sendgrid/mail/send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      personalizations: [{ to: [{ email: to }] }],
      from: { email: 'noreply@myapp.com' },
      subject: subject,
      content: [{ type: 'text/html', value: content }]
    })
  });
  
  return response.json();
};
```

## Deployment Process

### 1. Worker Generation
```ruby
# When app is deployed, generate Workers for:
app.app_oauth_providers.enabled.each do |provider|
  worker_code = provider.generate_worker_code
  deploy_oauth_worker(app, provider, worker_code)
end

app.app_api_integrations.enabled.each do |integration|
  worker_code = integration.generate_worker_code(app.app_api_integrations.enabled)
  deploy_api_worker(app, worker_code)
end
```

### 2. Environment Variables
```ruby
# Collect all secrets for Worker environment
env_vars = {}
app.app_oauth_providers.enabled.each do |provider|
  env_vars.merge!(provider.worker_env_vars)
end
app.app_api_integrations.enabled.each do |integration|
  env_vars.merge!(integration.worker_env_vars)
end

# Deploy to Cloudflare with encrypted environment
deploy_worker_with_secrets(worker_code, env_vars)
```

### 3. DNS Configuration
```
# OAuth Worker subdomain
auth-worker.app123.overskill.app -> Cloudflare Worker

# API Proxy subdomain  
api-worker.app123.overskill.app -> Cloudflare Worker

# Or single Worker with path routing
worker.app123.overskill.app/auth/* -> OAuth endpoints
worker.app123.overskill.app/api/* -> API proxy endpoints
```

## Security Considerations

### CORS Configuration
- Workers only accept requests from app's preview URL
- Preflight requests handled properly
- No wildcard origins in production

### Secret Management
- All API keys encrypted in database (Rails 7 `encrypts`)
- Environment variables injected securely into Workers
- No secrets exposed in client-side code
- Rotation strategy for compromised keys

### Rate Limiting
- Implement per-app rate limiting in Workers
- Respect third-party API rate limits
- Monitor usage and costs

### Error Handling
- Don't expose sensitive error details to client
- Log errors securely for debugging
- Graceful degradation when APIs are unavailable

## Competitive Advantages

### vs. Lovable/Base44
1. **True Backend Integration**: Not just UI generation
2. **Secure Secret Management**: No client-side API keys
3. **Production-Ready**: Proper authentication flows
4. **Cost-Effective**: Cloudflare Workers pricing
5. **Global Performance**: Edge deployment

### vs. Traditional Development
1. **Zero Infrastructure Setup**: No server management
2. **Instant Deployment**: Generated and deployed automatically
3. **Built-in Security**: Best practices enforced
4. **Simplified Integration**: Pre-configured common services

## Usage Examples

### E-commerce App
```javascript
// Generated app with Stripe + SendGrid integration
const CheckoutForm = () => {
  const processPayment = async (paymentMethod) => {
    // Create payment via proxy (secure)
    const payment = await fetch(`${WORKER_URL}/stripe/payment_intents`, {
      method: 'POST',
      body: JSON.stringify({ 
        amount: total * 100,
        payment_method: paymentMethod.id 
      })
    });
    
    if (payment.succeeded) {
      // Send receipt email via proxy (secure)
      await fetch(`${WORKER_URL}/sendgrid/mail/send`, {
        method: 'POST',
        body: JSON.stringify({
          to: customer.email,
          subject: 'Order Confirmation',
          template_id: 'receipt_template'
        })
      });
    }
  };
};
```

### SaaS App with Authentication
```javascript
// Generated app with Google OAuth + OpenAI integration
const App = () => {
  const [user, setUser] = useState(null);
  
  const handleLogin = () => {
    window.location.href = `${WORKER_URL}/auth/google`;
  };
  
  const generateContent = async (prompt) => {
    // AI generation via proxy (secure)
    const response = await fetch(`${WORKER_URL}/openai/chat/completions`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${userToken}` },
      body: JSON.stringify({
        model: 'gpt-4',
        messages: [{ role: 'user', content: prompt }]
      })
    });
    
    return response.json();
  };
};
```

## Monitoring and Analytics

### Worker Analytics
- Request volume and latency
- Error rates by integration
- Cost tracking per app
- Usage patterns analysis

### Security Monitoring
- Failed authentication attempts
- Unusual API usage patterns
- Rate limit violations
- CORS violations

## Future Enhancements

1. **More OAuth Providers**: Twitter, LinkedIn, Microsoft
2. **Webhook Support**: Secure webhook handling
3. **GraphQL Proxying**: Apollo Federation support
4. **Advanced Analytics**: Custom metrics and dashboards
5. **Team Collaboration**: Shared integrations across team

This system positions OverSkill as the only AI code generator with true production-ready backend integration capabilities, addressing the major gap in the current market.