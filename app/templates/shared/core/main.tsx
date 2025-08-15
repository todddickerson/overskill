import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './index.css';

// {{AI_GLOBALS_START}} - AI can add global configurations here
// Example: Initialize analytics, error tracking, etc.
// {{AI_GLOBALS_END}}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);