module Auth
  # OAuth service for handling authentication in Cloudflare Workers
  # Supports Google, GitHub, and other OAuth providers
  class OauthService
    def initialize(app)
      @app = app
    end

    # Generate OAuth configuration for Worker
    def oauth_config_for_worker
      {
        google: {
          client_id: ENV["GOOGLE_CLIENT_ID"],
          redirect_uri: "#{@app.preview_url}/auth/callback/google",
          scopes: ["openid", "email", "profile"]
        },
        github: {
          client_id: ENV["GITHUB_CLIENT_ID"],
          redirect_uri: "#{@app.preview_url}/auth/callback/github",
          scopes: ["user:email"]
        }
      }.compact
    end

    # Generate OAuth JavaScript for Worker embedding
    def oauth_worker_code
      <<~JAVASCRIPT
        // OAuth handling for Cloudflare Worker
        async function handleOAuthCallback(request, env, provider) {
          const url = new URL(request.url);
          const code = url.searchParams.get('code');
          const state = url.searchParams.get('state');
          
          if (!code) {
            return new Response('Missing authorization code', { status: 400 });
          }
          
          try {
            // Exchange code for token
            const tokenData = await exchangeCodeForToken(provider, code, env);
            
            if (tokenData.error) {
              return new Response(`OAuth error: ${tokenData.error}`, { status: 400 });
            }
            
            // Get user info
            const userInfo = await getUserInfo(provider, tokenData.access_token);
            
            // Create session via Supabase Auth
            const sessionResult = await createSupabaseSession(userInfo, env);
            
            if (sessionResult.error) {
              return new Response(`Session error: ${sessionResult.error}`, { status: 500 });
            }
            
            // Redirect with session
            const redirectUrl = state || '/dashboard';
            const response = Response.redirect(redirectUrl, 302);
            
            // Set session cookie
            response.headers.set('Set-Cookie', 
              `session_token=${sessionResult.session.access_token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=604800`
            );
            
            return response;
            
          } catch (error) {
            console.error('OAuth callback error:', error);
            return new Response('Authentication failed', { status: 500 });
          }
        }
        
        async function exchangeCodeForToken(provider, code, env) {
          const configs = {
            google: {
              url: 'https://oauth2.googleapis.com/token',
              client_id: env.GOOGLE_CLIENT_ID,
              client_secret: env.GOOGLE_CLIENT_SECRET,
              redirect_uri: `${env.APP_URL}/auth/callback/google`
            },
            github: {
              url: 'https://github.com/login/oauth/access_token',
              client_id: env.GITHUB_CLIENT_ID,
              client_secret: env.GITHUB_CLIENT_SECRET,
              redirect_uri: `${env.APP_URL}/auth/callback/github`
            }
          };
          
          const config = configs[provider];
          if (!config) {
            return { error: 'Unsupported provider' };
          }
          
          const response = await fetch(config.url, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'Accept': 'application/json'
            },
            body: new URLSearchParams({
              client_id: config.client_id,
              client_secret: config.client_secret,
              code: code,
              grant_type: 'authorization_code',
              redirect_uri: config.redirect_uri
            })
          });
          
          if (!response.ok) {
            return { error: `Token exchange failed: ${response.status}` };
          }
          
          return await response.json();
        }
        
        async function getUserInfo(provider, accessToken) {
          const endpoints = {
            google: 'https://www.googleapis.com/oauth2/v2/userinfo',
            github: 'https://api.github.com/user'
          };
          
          const response = await fetch(endpoints[provider], {
            headers: {
              'Authorization': `Bearer ${accessToken}`,
              'Accept': 'application/json'
            }
          });
          
          if (!response.ok) {
            throw new Error(`Failed to get user info: ${response.status}`);
          }
          
          const userData = await response.json();
          
          // Normalize user data across providers
          return {
            id: userData.id?.toString() || userData.login,
            email: userData.email,
            name: userData.name || userData.login,
            avatar_url: userData.picture || userData.avatar_url,
            provider: provider
          };
        }
        
        async function createSupabaseSession(userInfo, env) {
          const supabaseUrl = env.SUPABASE_URL;
          const supabaseKey = env.SUPABASE_ANON_KEY;
          
          if (!supabaseUrl || !supabaseKey) {
            return { error: 'Supabase not configured' };
          }
          
          // Sign in or sign up user via Supabase
          const response = await fetch(`${supabaseUrl}/auth/v1/signup`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'apikey': supabaseKey,
              'Authorization': `Bearer ${supabaseKey}`
            },
            body: JSON.stringify({
              email: userInfo.email,
              password: generateRandomPassword(), // Random password for OAuth users
              data: {
                name: userInfo.name,
                avatar_url: userInfo.avatar_url,
                provider: userInfo.provider,
                provider_id: userInfo.id
              }
            })
          });
          
          const result = await response.json();
          
          // If user exists, try to sign in instead
          if (result.error && result.error.message?.includes('already registered')) {
            return await signInExistingUser(userInfo, env);
          }
          
          return result;
        }
        
        async function signInExistingUser(userInfo, env) {
          // For OAuth users, we need to create a magic link or use alternative auth
          // This is simplified - in production, use proper OAuth identity linking
          const supabaseUrl = env.SUPABASE_URL;
          const serviceKey = env.SUPABASE_SERVICE_KEY;
          
          if (!serviceKey) {
            return { error: 'Cannot authenticate existing user without service key' };
          }
          
          // Use service key to find and authenticate user
          const response = await fetch(`${supabaseUrl}/rest/v1/auth.users?email=eq.${userInfo.email}`, {
            headers: {
              'apikey': serviceKey,
              'Authorization': `Bearer ${serviceKey}`
            }
          });
          
          if (!response.ok) {
            return { error: 'Failed to find existing user' };
          }
          
          const users = await response.json();
          if (users.length === 0) {
            return { error: 'User not found' };
          }
          
          // Generate session for existing user (simplified)
          return {
            session: {
              access_token: generateTemporaryToken(users[0]),
              user: users[0]
            }
          };
        }
        
        function generateRandomPassword() {
          return crypto.randomUUID() + crypto.randomUUID();
        }
        
        function generateTemporaryToken(user) {
          // In production, use proper JWT generation
          return btoa(JSON.stringify({
            sub: user.id,
            email: user.email,
            iat: Math.floor(Date.now() / 1000),
            exp: Math.floor(Date.now() / 1000) + 604800 // 1 week
          }));
        }
        
        // OAuth initiation URLs
        function getOAuthUrl(provider, env) {
          const configs = {
            google: {
              url: 'https://accounts.google.com/o/oauth2/v2/auth',
              params: {
                client_id: env.GOOGLE_CLIENT_ID,
                redirect_uri: `${env.APP_URL}/auth/callback/google`,
                response_type: 'code',
                scope: 'openid email profile',
                access_type: 'offline'
              }
            },
            github: {
              url: 'https://github.com/login/oauth/authorize',
              params: {
                client_id: env.GITHUB_CLIENT_ID,
                redirect_uri: `${env.APP_URL}/auth/callback/github`,
                scope: 'user:email'
              }
            }
          };
          
          const config = configs[provider];
          if (!config) return null;
          
          const params = new URLSearchParams(config.params);
          return `${config.url}?${params.toString()}`;
        }
      JAVASCRIPT
    end

    # Integration instructions for generated apps
    def integration_instructions
      {
        environment_variables: [
          "GOOGLE_CLIENT_ID",
          "GOOGLE_CLIENT_SECRET",
          "GITHUB_CLIENT_ID",
          "GITHUB_CLIENT_SECRET"
        ],
        worker_endpoints: [
          "GET /auth/login/:provider - Redirect to OAuth provider",
          "GET /auth/callback/:provider - Handle OAuth callback",
          "POST /auth/logout - Clear session",
          "GET /auth/user - Get current user info"
        ],
        frontend_integration: <<~JAVASCRIPT
          // Add to your React app
          function LoginButton() {
            const handleLogin = (provider) => {
              window.location.href = `/auth/login/${provider}`;
            };
            
            return (
              <div>
                <button onClick={() => handleLogin('google')}>
                  Login with Google
                </button>
                <button onClick={() => handleLogin('github')}>
                  Login with GitHub  
                </button>
              </div>
            );
          }
          
          // Check authentication status
          async function getCurrentUser() {
            const response = await fetch('/auth/user');
            if (response.ok) {
              return await response.json();
            }
            return null;
          }
        JAVASCRIPT
      }
    end
  end
end
