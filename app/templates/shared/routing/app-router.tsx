import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import ProtectedRoute from '../auth/protected-route';
import Login from '../auth/login';
import SignUp from '../auth/signup';
import ForgotPassword from '../auth/forgot-password';

// Import your app-specific pages here
// Example: import Dashboard from '../pages/Dashboard';
// Example: import Home from '../pages/Home';

export default function AppRouter() {
  return (
    <BrowserRouter>
      <Routes>
        {/* Public routes */}
        <Route path="/auth/login" element={<Login />} />
        <Route path="/auth/signup" element={<SignUp />} />
        <Route path="/auth/forgot-password" element={<ForgotPassword />} />
        
        {/* Protected routes */}
        <Route 
          path="/dashboard" 
          element={
            <ProtectedRoute>
              <div className="p-8">
                <h1 className="text-3xl font-bold text-gray-900">Dashboard</h1>
                <p className="mt-2 text-gray-600">Welcome to {{APP_NAME}}!</p>
              </div>
            </ProtectedRoute>
          } 
        />
        
        {/* App-specific routes will be added here by AI generation */}
        
        {/* Default redirects */}
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}