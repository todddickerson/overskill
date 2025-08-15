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
  // Badge visibility controlled by app settings
  const showBadge = window.APP_CONFIG?.showOverskillBadge !== false;
  
  if (!showBadge) {
    return null;
  }
  
  // Get the remix URL from the app config or use default
  const remixUrl = window.APP_CONFIG?.remixUrl || "https://overskill.app";
  
  return (
    <a
      href={remixUrl}
      target="_blank"
      rel="noopener noreferrer"
      className="overskill-badge"
      aria-label="Remix with OverSkill - Earn 30% referral commission"
      title="Keep this badge to earn up to 30% referral commissions!"
    >
      <svg
        width="20"
        height="20"
        viewBox="0 0 49 49"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        className="overskill-logo"
      >
        <rect width="49" height="49" rx="7.53846" fill="#E3F300"/>
        <path d="M22.5439 14.9289C22.5439 15.9138 23.3424 16.7122 24.3273 16.7122C25.3122 16.7122 26.1107 15.9138 26.1107 14.9289H24.3273H22.5439ZM26.1107 10.8271V9.04378H22.5439V10.8271H24.3273H26.1107ZM22.5439 38.1726C22.5439 39.1575 23.3424 39.956 24.3273 39.956C25.3122 39.956 26.1107 39.1575 26.1107 38.1726H24.3273H22.5439ZM26.1107 34.0709V32.2875H22.5439V34.0709H24.3273H26.1107ZM33.8979 22.7165C32.9129 22.7165 32.1145 23.515 32.1145 24.4999C32.1145 25.4848 32.9129 26.2833 33.8979 26.2833V24.4999V22.7165ZM37.9996 26.2833C38.9845 26.2833 39.7829 25.4848 39.7829 24.4999C39.7829 23.515 38.9845 22.7165 37.9996 22.7165V24.4999V26.2833ZM11 22.716C10.0151 22.716 9.21663 23.5145 9.21663 24.4994C9.21663 25.4843 10.0151 26.2828 11 26.2828V24.4994V22.716ZM15.1016 26.2828C16.0866 26.2828 16.885 25.4843 16.885 24.4994C16.885 23.5145 16.0866 22.716 15.1016 22.716V24.4994V26.2828ZM29.8337 16.4709C29.1373 17.1674 29.1373 18.2966 29.8337 18.993C30.5302 19.6895 31.6593 19.6895 32.3558 18.993L31.0948 17.732L29.8337 16.4709ZM35.2561 16.0927C35.9526 15.3962 35.9526 14.2671 35.2561 13.5706C34.5597 12.8742 33.4305 12.8742 32.7341 13.5706L33.9951 14.8316L35.2561 16.0927ZM9.73976 36.5655C9.04331 37.262 9.04331 38.3911 9.73976 39.0876C10.4362 39.784 11.5654 39.784 12.2618 39.0876L11.0008 37.8265L9.73976 36.5655ZM18.8208 32.5286C19.5173 31.8321 19.5173 30.7029 18.8208 30.0065C18.1244 29.31 16.9952 29.31 16.2988 30.0065L17.5598 31.2675L18.8208 32.5286ZM16.2988 18.993C16.9952 19.6895 18.1244 19.6895 18.8208 18.993C19.5173 18.2966 19.5173 17.1674 18.8208 16.4709L17.5598 17.732L16.2988 18.993ZM15.9205 13.5706C15.224 12.8742 14.0949 12.8742 13.3984 13.5706C12.702 14.2671 12.702 15.3962 13.3984 16.0927L14.6595 14.8316L15.9205 13.5706ZM32.734 35.4289C33.4304 36.1254 34.5596 36.1254 35.256 35.4289C35.9525 34.7325 35.9525 33.6033 35.256 32.9069L33.995 34.1679L32.734 35.4289ZM32.3557 30.0065C31.6593 29.3101 30.5301 29.3101 29.8336 30.0065C29.1372 30.703 29.1372 31.8321 29.8336 32.5286L31.0947 31.2676L32.3557 30.0065ZM24.3273 14.9289H26.1107V10.8271H24.3273H22.5439V14.9289H24.3273ZM24.3273 38.1726H26.1107V34.0709H24.3273H22.5439V38.1726H24.3273ZM33.8979 24.4999V26.2833H37.9996V24.4999V22.7165H33.8979V24.4999ZM11 24.4994V26.2828H15.1016V24.4994V22.716H11V24.4994ZM31.0948 17.732L32.3558 18.993L35.2561 16.0927L33.9951 14.8316L32.7341 13.5706L29.8337 16.4709L31.0948 17.732ZM11.0008 37.8265L12.2618 39.0876L18.8208 32.5286L17.5598 31.2675L16.2988 30.0065L9.73976 36.5655L11.0008 37.8265ZM17.5598 17.732L18.8208 16.4709L15.9205 13.5706L14.6595 14.8316L13.3984 16.0927L16.2988 18.993L17.5598 17.732ZM33.995 34.1679L35.256 32.9069L32.3557 30.0065L31.0947 31.2676L29.8336 32.5286L32.734 35.4289L33.995 34.1679Z" fill="#6A7107"/>
      </svg>
      <span>Remix with OverSkill</span>
    </a>
  );
}

export default App;
