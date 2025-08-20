import React from 'react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import ProtectedRoute from '../auth/protected-route';
import Login from '../auth/login';
import SignUp from '../auth/signup';
import ForgotPassword from '../auth/forgot-password';

// {{AI_IMPORTS_START}} - AI will add page imports here
// IMPORTANT: Import pages from '../pages/' directory
// Example: import Dashboard from '../pages/Dashboard';
// Example: import Index from '../pages/Index';  // For landing pages
// {{AI_IMPORTS_END}}

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
        
        {/* {{AI_ROUTES_START}} - AI will add app-specific routes here */}
        {/* IMPORTANT: For landing pages, add: <Route path="/" element={<Index />} /> */}
        {/* For apps with main functionality, add your routes here */}
        {/* {{AI_ROUTES_END}} */}
        
        {/* Default redirects - AI should update these based on app type */}
        <Route path="/" element={<Navigate to="/dashboard" replace />} />
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </BrowserRouter>
  );
}