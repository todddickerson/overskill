class Account::AppSettingsController < Account::ApplicationController
  before_action :set_app
  before_action :set_app_setting, only: [:show, :edit, :update, :destroy]
  
  def index
    @app_settings = @app.app_settings.order(:setting_type, :key)
    @grouped_settings = @app_settings.group_by(&:setting_type)
  end
  
  def new
    @app_setting = @app.app_settings.build
  end
  
  def create
    @app_setting = @app.app_settings.build(app_setting_params)
    
    if @app_setting.save
      respond_to do |format|
        format.html { redirect_to account_app_app_settings_path(@app), notice: 'Setting was successfully created.' }
        format.turbo_stream
      end
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def update
    if @app_setting.update(app_setting_params)
      respond_to do |format|
        format.html { redirect_to account_app_app_settings_path(@app), notice: 'Setting was successfully updated.' }
        format.turbo_stream
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @app_setting.destroy
    redirect_to account_app_app_settings_path(@app), notice: 'Setting was successfully removed.'
  end
  
  private
  
  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  def set_app_setting
    @app_setting = @app.app_settings.find(params[:id])
  end
  
  def app_setting_params
    params.require(:app_setting).permit(:key, :value, :description, :setting_type, :encrypted)
  end
end