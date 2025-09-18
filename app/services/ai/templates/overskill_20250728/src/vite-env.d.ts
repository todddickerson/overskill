/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_APP_ID: string
  readonly VITE_OWNER_ID: string
  readonly VITE_ENVIRONMENT: string
  readonly VITE_R2_BASE_URL: string
  readonly VITE_USE_LOCAL_ASSETS: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}

// App configuration interface
interface AppConfig {
  showOverskillBadge?: boolean;
  remixUrl?: string;
  appId?: string;
  ownerId?: string;
  environment?: string;
}

// Extend Window interface to include APP_CONFIG
declare global {
  interface Window {
    APP_CONFIG?: AppConfig;
  }
}