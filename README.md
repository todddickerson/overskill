# Overskill

## Getting Started

1. You must have the following dependencies installed:

     - Ruby 3
          - See [`.ruby-version`](.ruby-version) for the specific version.
     - Node 19
          - See [`.nvmrc`](.nvmrc) for the specific version.
     - PostgreSQL 14
     - Redis 6.2
     - [Chrome](https://www.google.com/search?q=chrome) (for headless browser tests)

    If you don't have these installed, you can use [rails.new](https://rails.new) to help with the process.

2. Run the `bin/setup` script.
3. Start the application with `bin/dev`.
4. Visit http://localhost:3000.

## Assets: JS and CSS builds

The app’s assets are built with esbuild (JS) and PostCSS/Tailwind (CSS).

- Build everything once:
  - npm run build
- Build JS only / watch:
  - npm run build:js
  - npm run build:js:watch
- Build CSS only / watch (application stylesheet):
  - npm run build:css
  - npm run build:css:watch
- Build mailer CSS only / watch (used for Action Mailer templates):
  - npm run build:mailer:css
  - npm run build:mailer:css:watch

Theme selection
- The build respects THEME, which controls which theme tokens are applied during CSS processing.
- Default is the app’s standard theme. To force the light theme:
  - THEME=light npm run build:css
  - THEME=light npm run build:mailer:css
  - For watchers, you can also use convenience scripts:
    - npm run light:build:css
    - npm run light:build:mailer:css

Output files
- JS and CSS outputs are written to app/assets/builds/ and are served by Rails in development.

## Information about Bullet Train
If this is your first time working on a Bullet Train application, be sure to review the [Bullet Train Basic Techniques](https://bullettrain.co/docs/getting-started) and the [Bullet Train Developer Documentation](https://bullettrain.co/docs).

