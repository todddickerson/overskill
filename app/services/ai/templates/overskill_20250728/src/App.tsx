import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { ThemeProvider } from "next-themes";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import "./App.css";

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      retry: 1,
      refetchOnWindowFocus: false,
    },
  },
});

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
        <Router>
          <Routes>
            <Route path="/" element={<Index />} />
            <Route path="*" element={<NotFound />} />
          </Routes>
          <Toaster />
          <Sonner />
          <OverSkillBadge />
        </Router>
      </ThemeProvider>
    </QueryClientProvider>
  );
}

// OverSkill Branding Badge
function OverSkillBadge() {
  // Safely access window.APP_CONFIG with fallback
  const appConfig = (window as any).APP_CONFIG || {};
  const showBadge = appConfig.showOverskillBadge !== false;
  
  if (!showBadge) {
    return null;
  }
  
  // Get the remix URL from the app config or use default
  const remixUrl = appConfig.remixUrl || "https://overskill.app";
  
  return (
    <a
      href={remixUrl}
      target="_blank"
      rel="noopener noreferrer"
      className="fixed bottom-4 right-4 bg-gradient-to-r from-blue-500 to-purple-600 text-white px-3 py-2 rounded-lg text-sm font-medium shadow-lg hover:shadow-xl transition-all duration-200 hover:scale-105 z-50"
      title="Remix this app on OverSkill"
    >
      🚀 Remix on OverSkill
    </a>
  );
}

export default App;