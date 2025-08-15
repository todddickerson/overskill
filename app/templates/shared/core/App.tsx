import React from 'react';
import AppRouter from './routing/app-router';
import { Toaster } from 'react-hot-toast';

// {{AI_APP_IMPORTS_START}} - AI can add app-level imports here
// Example: import { ThemeProvider } from './contexts/ThemeContext';
// {{AI_APP_IMPORTS_END}}

function App() {
  return (
    <>
      {/* {{AI_PROVIDERS_START}} - AI can wrap with providers here */}
      <AppRouter />
      <Toaster position="top-right" />
      {/* {{AI_PROVIDERS_END}} */}
    </>
  );
}

export default App;