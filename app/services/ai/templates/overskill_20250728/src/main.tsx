import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App.tsx";
import "./index.css";

// Error boundary for production (simplified)
window.addEventListener('error', (event) => {
  console.error('Application Error:', event.message, {
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
