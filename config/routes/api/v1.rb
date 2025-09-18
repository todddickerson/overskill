# See `config/routes.rb` for details.
collection_actions = [:index, :new, :create] # standard:disable Lint/UselessAssignment
extending = {only: []}

shallow do
  namespace :v1 do
    # user specific resources.
    resources :users, extending do
      namespace :oauth do
        # 🚅 super scaffolding will insert new oauth providers above this line.
      end

      # routes for standard user actions and resources are configured in the `bullet_train` gem, but you can add more here.
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
        # 🚅 super scaffolding will insert new integration installations above this line.
      end

      resources :creator_profiles
      resources :follows
      resources :apps do
        resources :app_versions
        resources :app_files
        resources :app_generations
        resources :app_collaborators
        resources :app_settings
        resources :app_security_policies
        resources :app_audit_logs
        resources :app_env_vars

        member do
          post :create_preview_environment
        end
      end
    end

    # Iframe bridge routes - outside of teams scope for direct app access
    resources :iframe_bridge, only: [], param: :app_id do
      member do
        post :log
        get :console_logs
        get :network_requests
        post :setup
        delete :clear
      end
    end
  end
end
