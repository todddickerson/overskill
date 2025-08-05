# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppAuditLogsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_audit_log, through: :app, through_association: :app_audit_logs

    # GET /api/v1/apps/:app_id/app_audit_logs
    def index
    end

    # GET /api/v1/app_audit_logs/:id
    def show
    end

    # POST /api/v1/apps/:app_id/app_audit_logs
    def create
      if @app_audit_log.save
        render :show, status: :created, location: [:api, :v1, @app_audit_log]
      else
        render json: @app_audit_log.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_audit_logs/:id
    def update
      if @app_audit_log.update(app_audit_log_params)
        render :show
      else
        render json: @app_audit_log.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_audit_logs/:id
    def destroy
      @app_audit_log.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_audit_log_params
        strong_params = params.require(:app_audit_log).permit(
          *permitted_fields,
          :action_type,
          :performed_by,
          :target_resource,
          :resource_id,
          :change_details,
          :ip_address,
          :user_agent,
          :occurred_at,
          # 🚅 super scaffolding will insert new fields above this line.
          *permitted_arrays,
          # 🚅 super scaffolding will insert new arrays above this line.
        )

        process_params(strong_params)

        strong_params
      end
    end

    include StrongParameters
  end
else
  class Api::V1::AppAuditLogsController
  end
end
