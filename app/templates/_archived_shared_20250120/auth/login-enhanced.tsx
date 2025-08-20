import React, { useState } from 'react';
import { Link } from 'react-router-dom';
import { supabase } from '../../lib/supabase-client';

// Import shadcn/ui components if available, fallback to basic elements
let Button: any, Card: any, CardHeader: any, CardContent: any, CardTitle: any, CardDescription: any;
let Input: any, Label: any;

try {
  const buttonModule = require('@/components/ui/button');
  Button = buttonModule.Button;
  
  const cardModule = require('@/components/ui/card');
  Card = cardModule.Card;
  CardHeader = cardModule.CardHeader;
  CardContent = cardModule.CardContent;
  CardTitle = cardModule.CardTitle;
  CardDescription = cardModule.CardDescription;
  
  const inputModule = require('@/components/ui/input');
  Input = inputModule.Input;
  
  const labelModule = require('@/components/ui/label');
  Label = labelModule.Label;
} catch (e) {
  // Fallback to basic HTML elements
  Button = ({ children, ...props }: any) => <button {...props}>{children}</button>;
  Card = ({ children, className = '', ...props }: any) => <div className={`border rounded-lg ${className}`} {...props}>{children}</div>;
  CardHeader = ({ children, className = '', ...props }: any) => <div className={`p-6 ${className}`} {...props}>{children}</div>;
  CardContent = ({ children, className = '', ...props }: any) => <div className={`p-6 pt-0 ${className}`} {...props}>{children}</div>;
  CardTitle = ({ children, className = '', ...props }: any) => <h2 className={`text-2xl font-bold ${className}`} {...props}>{children}</h2>;
  CardDescription = ({ children, className = '', ...props }: any) => <p className={`text-gray-600 ${className}`} {...props}>{children}</p>;
  Input = (props: any) => <input className="w-full px-3 py-2 border rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500" {...props} />;
  Label = ({ children, className = '', ...props }: any) => <label className={`block text-sm font-medium mb-1 ${className}`} {...props}>{children}</label>;
}

export default function LoginEnhanced() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) {
        setError(error.message);
      } else {
        // Redirect to dashboard or home
        window.location.href = '/dashboard';
      }
    } catch (err) {
      setError('An unexpected error occurred');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle>Welcome back</CardTitle>
          <CardDescription>
            Enter your credentials to sign in to {{APP_NAME}}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleLogin} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="Enter your email"
                value={email}
                onChange={(e: any) => setEmail(e.target.value)}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                placeholder="Enter your password"
                value={password}
                onChange={(e: any) => setPassword(e.target.value)}
                required
              />
            </div>
            
            {error && (
              <div className="text-red-600 text-sm text-center">{error}</div>
            )}
            
            <div className="flex items-center justify-between">
              <Link 
                to="/auth/forgot-password"
                className="text-sm text-blue-600 hover:underline"
              >
                Forgot password?
              </Link>
            </div>
            
            <Button 
              type="submit" 
              className="w-full bg-blue-600 hover:bg-blue-700 text-white py-2 px-4 rounded-md transition-colors"
              disabled={loading}
            >
              {loading ? 'Signing in...' : 'Sign in'}
            </Button>
            
            <div className="text-center text-sm">
              Don't have an account?{' '}
              <Link to="/auth/signup" className="text-blue-600 hover:underline">
                Sign up
              </Link>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  );
}