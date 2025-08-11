import React, { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase-client';
import type { User } from '@supabase/supabase-js';

interface CurrentUserAvatarProps {
  size?: 'sm' | 'md' | 'lg';
  showFallback?: boolean;
  className?: string;
}

export default function CurrentUserAvatar({ 
  size = 'md', 
  showFallback = true,
  className = ''
}: CurrentUserAvatarProps) {
  const [user, setUser] = useState<User | null>(null);
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const [name, setName] = useState<string>('');

  useEffect(() => {
    // Get current user
    const getCurrentUser = async () => {
      const { data: { user }, error } = await supabase.auth.getUser();
      
      if (error) {
        console.error('Error fetching user:', error);
        return;
      }
      
      setUser(user);
      
      if (user) {
        // Extract image URL from user metadata
        const avatarUrl = user.user_metadata?.avatar_url || 
                         user.user_metadata?.picture ||
                         user.user_metadata?.image_url;
        setImageUrl(avatarUrl);
        
        // Extract name from user metadata
        const fullName = user.user_metadata?.full_name || 
                        user.user_metadata?.name ||
                        user.user_metadata?.display_name ||
                        user.email?.split('@')[0] || 
                        'User';
        setName(fullName);
      }
    };

    getCurrentUser();

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        if (event === 'SIGNED_OUT') {
          setUser(null);
          setImageUrl(null);
          setName('');
        } else if (event === 'SIGNED_IN' && session?.user) {
          getCurrentUser();
        }
      }
    );

    return () => subscription.unsubscribe();
  }, []);

  // Size classes
  const sizeClasses = {
    sm: 'h-8 w-8 text-xs',
    md: 'h-10 w-10 text-sm',
    lg: 'h-12 w-12 text-base'
  };

  // Get user initials
  const getInitials = (name: string): string => {
    if (!name) return '?';
    return name
      .split(' ')
      .map(part => part.charAt(0).toUpperCase())
      .join('')
      .substring(0, 2);
  };

  // If no user and not showing fallback, return null
  if (!user && !showFallback) {
    return null;
  }

  return (
    <div className={`relative inline-flex items-center justify-center ${sizeClasses[size]} rounded-full bg-gray-100 overflow-hidden ${className}`}>
      {imageUrl ? (
        <img
          src={imageUrl}
          alt={name}
          className="h-full w-full object-cover"
          onError={() => setImageUrl(null)}
        />
      ) : (
        <span className="font-medium text-gray-600">
          {user ? getInitials(name) : '?'}
        </span>
      )}
      
      {/* Online indicator (optional) */}
      {user && (
        <span className="absolute -bottom-0 -right-0 block h-2.5 w-2.5 rounded-full bg-green-400 ring-2 ring-white" />
      )}
    </div>
  );
}