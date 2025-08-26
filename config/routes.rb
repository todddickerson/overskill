Rails.application.routes.draw do
  # See `config/routes/*.rb` to customize these configurations.
  draw "concerns"
  draw "devise"
  draw "sidekiq"
  draw "avo"

  # `collection_actions` is automatically super scaffolded to your routes file when creating certain objects.
  # This is helpful to have around when working with shallow routes and complicated model namespacing. We don't use this
  # by default, but sometimes Super Scaffolding will generate routes that use this for `only` and `except` options.
  collection_actions = [:index, :new, :create] # standard:disable Lint/UselessAssignment

  # This helps mark `resources` definitions below as not actually defining the routes for a given resource, but just
  # making it possible for developers to extend definitions that are already defined by the `bullet_train` Ruby gem.
  # TODO Would love to get this out of the application routes file.
  extending = {only: []}

  scope module: "public" do
    # To keep things organized, we put non-authenticated controllers in the `Public::` namespace.
    # The root `/` path is routed to `Public::HomeController#index` by default. You can set it
    # to whatever you want by doing something like this:
    # root to: "my_new_root_controller#index"
    
    # Simple app generator - the main entry point
    root to: "generator#index"
    resources :generator, only: [:index, :create]
  end

  # Admin analytics dashboard (protected)
  authenticate :user, ->(user) { user.email == ENV["SUPER_ADMIN_EMAIL"] } do
    mount AhoyCaptain::Engine, at: "/admin/analytics"
    
    # System optimization metrics dashboard
    namespace :admin do
      resources :metrics, only: [:index]
    end
  end

  namespace :webhooks do
    # Supabase authentication webhooks
    post "supabase/auth_event", to: "supabase#auth_event"
    
    namespace :incoming do
      namespace :oauth do
        resources :google_oauth2_account_webhooks if google_oauth2_enabled?
        resources :github_account_webhooks if github_enabled?
        # 🚅 super scaffolding will insert new oauth provider webhooks above this line.
      end
    end
  end

  namespace :api do
    draw "api/v1"
    # 🚅 super scaffolding will insert new api versions above this line.
  end

  namespace :account do
    shallow do
      # The account root `/` path is routed to `Account::Dashboard#index` by default. You can set it
      # to whatever you want by doing something like this:
      # root to: "some_other_root_controller#index", as: "dashboard"

      # user-level onboarding tasks.
      namespace :onboarding do
        # routes for standard onboarding steps are configured in the `bullet_train` gem, but you can add more here.
      end

      # user specific resources.
      resources :users, extending do
        namespace :oauth do
          resources :google_oauth2_accounts if google_oauth2_enabled?
          resources :github_accounts if github_enabled?
          # 🚅 super scaffolding will insert new oauth providers above this line.
        end

        # routes for standard user actions and resources are configured in the `bullet_train` gem, but you can add more here.
      end
      
      # Supabase sync management (admin only)
      resources :supabase_sync, only: [:index] do
        collection do
          post :sync_all
          get :webhook_logs
        end
        member do
          post :sync_user
          get :check_status
        end
      end

      # team-level resources.
      resources :teams, extending do
        # routes for many teams actions and resources are configured in the `bullet_train` gem, but you can add more here.

        # add your resources here.

        resources :invitations, extending do
          # routes for standard invitation actions and resources are configured in the `bullet_train` gem, but you can add more here.
        end

        resources :memberships, extending do
          # routes for standard membership actions and resources are configured in the `bullet_train` gem, but you can add more here.
        end

        namespace :integrations do
          resources :google_oauth2_installations if google_oauth2_enabled?
          resources :github_installations if github_enabled?
          # 🚅 super scaffolding will insert new integration installations above this line.
        end

        # Database configuration for hybrid architecture
        resource :database_config, controller: "team_database_configs", only: [:show, :edit, :update] do
          member do
            post :test_connection
            get :export_instructions
            get :migration_status
            get "export_app/:app_id", action: :export_app, as: :export_app
            post :export_all_apps
            post :import_data
          end
        end

        resources :creator_profiles
        resources :follows
        resources :apps do
          member do
            get :deployment_info
            get :activity_monitor
            post :deploy
            post :publish, controller: "app_deployments"
            post :unpublish, controller: "app_deployments"
            patch :subdomain, action: :update_subdomain, controller: "app_deployments"
            post :generate_logo
            post :upload_logo
            post :debug_error
          end
          
          resources :app_files, only: [:index]
          
          # Chat interface (may be deprecated in favor of editor)
          resource :chat, controller: "app_chats", only: [:show, :create]
          
          # Main editor interface at /account/apps/:id/editor
          resource :editor, controller: "app_editors", only: [:show] do
            post :create_message
            patch "files/:file_id", action: :update_file, as: :file
          end
          
          # Version management actions
          post :update_preview, controller: "app_editors"
          post "versions/:version_id/restore", action: :restore_version, controller: "app_editors", as: :restore_version
          post "versions/:version_id/bookmark", action: :bookmark_version, controller: "app_editors", as: :bookmark_version  
          get "versions/:version_id/compare", action: :compare_version, controller: "app_editors", as: :compare_version
          
          # Version list for history modal
          get :versions, controller: "app_editors"
          
          # Preview iframe and file serving at /account/apps/:id/preview
          resource :preview, controller: "app_previews", only: [:show] do
            get "files/*path", action: :serve_file, as: :file, format: false
          end
          
          # Dashboard interface for database management
          resource :dashboard, controller: "app_dashboards", only: [:show] do
            get :data
            post :create_table
            patch "tables/:table_id", action: :update_table, as: :update_table
            delete "tables/:table_id", action: :delete_table, as: :delete_table
            get "tables/:table_id/data", action: :table_data, as: :table_data
            get "tables/:table_id/schema", action: :table_schema, as: :table_schema
            post "tables/:table_id/columns", action: :create_column, as: :create_column
            patch "tables/:table_id/columns/:column_id", action: :update_column, as: :update_column
            delete "tables/:table_id/columns/:column_id", action: :delete_column, as: :delete_column
            post "tables/:table_id/records", action: :create_record, as: :create_record
            patch "tables/:table_id/records/:record_id", action: :update_record, as: :update_record
            delete "tables/:table_id/records/:record_id", action: :delete_record, as: :delete_record
          end

          resources :app_versions do
            member do
              get :preview
              get "files/*path", action: :serve_file, as: :file, format: false
              get :compare
              post :restore
              post :bookmark
            end
          end
          resources :app_files
          resources :app_generations
          resources :app_collaborators
          
          # API call logging and monitoring
          resources :api_calls, controller: "app_api_calls", only: [:index, :show, :destroy] do
            collection do
              delete :clear_all
            end
          end
          
          # Security and audit features (transparent, unlike Base44)
          resources :security_policies, controller: "app_security_policies", only: [:index, :show]
          resources :audit_logs, controller: "app_audit_logs", only: [:index, :show] do
            collection do
              get :search
              get :compliance_report
              get :export
            end
          end
          
          # Deployment management
          resource :deployment, controller: "app_deployments", only: [:show] do
            member do
              post :deploy
              get :status
              post :rollback
              get :logs
            end
          end
          
          # App settings (simplified for non-technical users)
          resources :app_settings
          resources :app_security_policies
          resources :app_audit_logs
          resources :app_env_vars
        end
      end
    end
  end
end
