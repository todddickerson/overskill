# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppFilesController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_file, through: :app, through_association: :app_files

    # GET /api/v1/apps/:app_id/app_files
    def index
    end

    # GET /api/v1/app_files/:id
    def show
    end

    # POST /api/v1/apps/:app_id/app_files
    def create
      if @app_file.save
        render :show, status: :created, location: [:api, :v1, @app_file]
      else
        render json: @app_file.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_files/:id
    def update
      if @app_file.update(app_file_params)
        render :show
      else
        render json: @app_file.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_files/:id
    def destroy
      @app_file.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_file_params
        strong_params = params.require(:app_file).permit(
          *permitted_fields,
          :path,
          :content,
          :file_type,
          :size_bytes,
          :checksum,
          :is_entry_point,
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
  class Api::V1::AppFilesController
  end
end
