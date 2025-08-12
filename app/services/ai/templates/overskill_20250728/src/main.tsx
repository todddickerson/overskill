import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { initializeApp } from "./lib/supabase";
import { analytics } from "./lib/analytics";

// Initialize app with RLS context
initializeApp().catch(console.error);

// Error boundary for production
window.addEventListener('error', (event) => {
  analytics.trackError(new Error(event.message), {
    filename: event.filename,
    lineno: event.lineno,
    colno: event.colno
  });
});

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
