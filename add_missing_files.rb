#!/usr/bin/env ruby
require_relative "config/environment"

app = App.find(1027)
puts "Adding missing files for #{app.name}..."

# Create lib/utils.ts if missing
utils_file = app.app_files.find_by(path: "src/lib/utils.ts")
if !utils_file
  puts "Creating src/lib/utils.ts..."
  app.app_files.create!(
    path: "src/lib/utils.ts",
    content: <<~TS,
      import { type ClassValue, clsx } from "clsx"
      import { twMerge } from "tailwind-merge"

      export function cn(...inputs: ClassValue[]) {
        return twMerge(clsx(inputs))
      }
    TS
    file_type: "typescript",
    team: app.team
  )
end

# Create lib/analytics.ts if missing
analytics_file = app.app_files.find_by(path: "src/lib/analytics.ts")
if !analytics_file
  puts "Creating src/lib/analytics.ts..."
  app.app_files.create!(
    path: "src/lib/analytics.ts",
    content: <<~TS,
      export const trackEvent = (event: string, properties?: Record<string, any>) => {
        console.log('Analytics Event:', event, properties);
        // Add your analytics implementation here
      };
    TS
    file_type: "typescript",
    team: app.team
  )
end

# Create hooks/use-mobile.tsx if missing
use_mobile = app.app_files.find_by(path: "src/hooks/use-mobile.tsx")
if !use_mobile
  puts "Creating src/hooks/use-mobile.tsx..."
  app.app_files.create!(
    path: "src/hooks/use-mobile.tsx",
    content: <<~TS,
      import * as React from "react"

      const MOBILE_BREAKPOINT = 768

      export function useIsMobile() {
        const [isMobile, setIsMobile] = React.useState<boolean | undefined>(undefined)

        React.useEffect(() => {
          const mql = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`)
          const onChange = () => {
            setIsMobile(window.innerWidth < MOBILE_BREAKPOINT)
          }
          mql.addEventListener("change", onChange)
          setIsMobile(window.innerWidth < MOBILE_BREAKPOINT)
          return () => mql.removeEventListener("change", onChange)
        }, [])

        return !!isMobile
      }
    TS
    file_type: "typescript",
    team: app.team
  )
end

# Create sonner component if missing
sonner = app.app_files.find_by(path: "src/components/ui/sonner.tsx")
if !sonner
  puts "Creating src/components/ui/sonner.tsx..."
  app.app_files.create!(
    path: "src/components/ui/sonner.tsx",
    content: <<~TS,
      import { useTheme } from "next-themes"
      import { Toaster as Sonner } from "sonner"

      type ToasterProps = React.ComponentProps<typeof Sonner>

      const Toaster = ({ ...props }: ToasterProps) => {
        const { theme = "system" } = useTheme()

        return (
          <Sonner
            theme={theme as ToasterProps["theme"]}
            className="toaster group"
            toastOptions={{
              classNames: {
                toast:
                  "group toast group-[.toaster]:bg-background group-[.toaster]:text-foreground group-[.toaster]:border-border group-[.toaster]:shadow-lg",
                description: "group-[.toast]:text-muted-foreground",
                actionButton:
                  "group-[.toast]:bg-primary group-[.toast]:text-primary-foreground",
                cancelButton:
                  "group-[.toast]:bg-muted group-[.toast]:text-muted-foreground",
              },
            }}
            {...props}
          />
        )
      }

      export { Toaster }
    TS
    file_type: "typescript",
    team: app.team
  )
end

# Create Footer component if missing
footer = app.app_files.find_by(path: "src/components/Footer.tsx")
if !footer
  puts "Creating src/components/Footer.tsx..."
  app.app_files.create!(
    path: "src/components/Footer.tsx",
    content: <<~TS,
      export default function Footer() {
        return (
          <footer className="bg-gray-900 text-white py-12">
            <div className="container mx-auto px-4">
              <div className="text-center">
                <p>&copy; 2024 Pageforge. All rights reserved.</p>
              </div>
            </div>
          </footer>
        )
      }
    TS
    file_type: "typescript",
    team: app.team
  )
end

# Update package.json to include missing dependencies
package_json = app.app_files.find_by(path: "package.json")
if package_json
  puts "Updating package.json dependencies..."
  config = JSON.parse(package_json.content)

  # Add missing dependencies
  config["dependencies"] ||= {}
  config["dependencies"]["clsx"] ||= "^2.1.0"
  config["dependencies"]["tailwind-merge"] ||= "^2.2.0"
  config["dependencies"]["sonner"] ||= "^1.3.1"
  config["dependencies"]["next-themes"] ||= "^0.2.1"
  config["dependencies"]["class-variance-authority"] ||= "^0.7.0"
  config["dependencies"]["lucide-react"] ||= "^0.344.0"
  config["dependencies"]["@radix-ui/react-accordion"] ||= "^1.1.2"
  config["dependencies"]["@radix-ui/react-alert-dialog"] ||= "^1.0.5"
  config["dependencies"]["@radix-ui/react-avatar"] ||= "^1.0.4"
  config["dependencies"]["@radix-ui/react-checkbox"] ||= "^1.0.4"
  config["dependencies"]["@radix-ui/react-dialog"] ||= "^1.0.5"
  config["dependencies"]["@radix-ui/react-dropdown-menu"] ||= "^2.0.6"
  config["dependencies"]["@radix-ui/react-label"] ||= "^2.0.2"
  config["dependencies"]["@radix-ui/react-popover"] ||= "^1.0.7"
  config["dependencies"]["@radix-ui/react-progress"] ||= "^1.0.3"
  config["dependencies"]["@radix-ui/react-radio-group"] ||= "^1.1.3"
  config["dependencies"]["@radix-ui/react-scroll-area"] ||= "^1.0.5"
  config["dependencies"]["@radix-ui/react-select"] ||= "^2.0.0"
  config["dependencies"]["@radix-ui/react-separator"] ||= "^1.0.3"
  config["dependencies"]["@radix-ui/react-slider"] ||= "^1.1.2"
  config["dependencies"]["@radix-ui/react-switch"] ||= "^1.0.3"
  config["dependencies"]["@radix-ui/react-tabs"] ||= "^1.0.4"
  config["dependencies"]["@radix-ui/react-toast"] ||= "^1.1.5"
  config["dependencies"]["@radix-ui/react-toggle"] ||= "^1.0.3"
  config["dependencies"]["@radix-ui/react-toggle-group"] ||= "^1.0.4"
  config["dependencies"]["@radix-ui/react-tooltip"] ||= "^1.0.7"
  config["dependencies"]["@radix-ui/react-hover-card"] ||= "^1.0.7"
  config["dependencies"]["@radix-ui/react-menubar"] ||= "^1.0.4"
  config["dependencies"]["@radix-ui/react-navigation-menu"] ||= "^1.1.4"
  config["dependencies"]["@radix-ui/react-context-menu"] ||= "^2.1.5"
  config["dependencies"]["@radix-ui/react-slot"] ||= "^1.0.2"
  config["dependencies"]["@radix-ui/react-collapsible"] ||= "^1.0.3"
  config["dependencies"]["cmdk"] ||= "^0.2.1"
  config["dependencies"]["date-fns"] ||= "^3.3.1"
  config["dependencies"]["embla-carousel-react"] ||= "^8.0.0"
  config["dependencies"]["input-otp"] ||= "^1.2.4"
  config["dependencies"]["react-day-picker"] ||= "^8.10.0"
  config["dependencies"]["react-hook-form"] ||= "^7.49.3"
  config["dependencies"]["react-resizable-panels"] ||= "^2.0.12"
  config["dependencies"]["recharts"] ||= "^2.12.0"
  config["dependencies"]["vaul"] ||= "^0.9.0"

  package_json.content = JSON.pretty_generate(config)
  package_json.save!
  puts "✅ Updated package.json"
end

puts "\n✅ Added all missing files!"
