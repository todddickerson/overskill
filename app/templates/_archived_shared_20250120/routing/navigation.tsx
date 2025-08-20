import React from 'react';
import { Link, useLocation } from 'react-router-dom';
import { getNavigationRoutes } from './route-config';
import { supabase } from '../../lib/supabase-client';

export default function Navigation() {
  const location = useLocation();
  const navigationRoutes = getNavigationRoutes();

  const handleSignOut = async () => {
    await supabase.auth.signOut();
    window.location.href = '/auth/login';
  };

  return (
    <nav className="bg-white shadow-sm border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between h-16">
          <div className="flex">
            <div className="flex-shrink-0 flex items-center">
              <h1 className="text-xl font-bold text-gray-900">{{APP_NAME}}</h1>
            </div>
            <div className="hidden sm:ml-6 sm:flex sm:space-x-8">
              {navigationRoutes.map((route) => (
                <Link
                  key={route.path}
                  to={route.path}
                  className={`inline-flex items-center px-1 pt-1 border-b-2 text-sm font-medium ${
                    location.pathname === route.path
                      ? 'border-indigo-500 text-gray-900'
                      : 'border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-700'
                  }`}
                >
                  {route.name}
                </Link>
              ))}
            </div>
          </div>
          <div className="flex items-center">
            <button
              onClick={handleSignOut}
              className="text-gray-500 hover:text-gray-700 px-3 py-2 rounded-md text-sm font-medium"
            >
              Sign out
            </button>
          </div>
        </div>
      </div>

      {/* Mobile menu */}
      <div className="sm:hidden">
        <div className="pt-2 pb-3 space-y-1">
          {navigationRoutes.map((route) => (
            <Link
              key={route.path}
              to={route.path}
              className={`block pl-3 pr-4 py-2 border-l-4 text-base font-medium ${
                location.pathname === route.path
                  ? 'bg-indigo-50 border-indigo-500 text-indigo-700'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-50 hover:border-gray-300'
              }`}
            >
              {route.name}
            </Link>
          ))}
          <button
            onClick={handleSignOut}
            className="block w-full text-left pl-3 pr-4 py-2 border-l-4 border-transparent text-gray-500 hover:text-gray-700 hover:bg-gray-50 hover:border-gray-300 text-base font-medium"
          >
            Sign out
          </button>
        </div>
      </div>
    </nav>
  );
}