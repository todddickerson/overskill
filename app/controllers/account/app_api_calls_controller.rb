class Account::AppApiCallsController < Account::ApplicationController
  include Account::Apps::ControllerBase
  
  before_action :set_app
  before_action :set_api_call, only: [:show, :destroy]
  
  def index
    @api_calls = @app.app_api_calls.recent.limit(100)
    
    # Filter by method if requested
    if params[:method].present?
      @api_calls = @api_calls.by_method(params[:method])
    end
    
    # Filter by date range if requested  
    if params[:start_date].present? && params[:end_date].present?
      start_date = Date.parse(params[:start_date])
      end_date = Date.parse(params[:end_date])
      @api_calls = @api_calls.where(occurred_at: start_date.beginning_of_day..end_date.end_of_day)
    end
    
    respond_to do |format|
      format.json { render json: @api_calls }
      format.html { redirect_to account_app_editor_path(@app) }
    end
  end
  
  def show
    respond_to do |format|
      format.json { render json: @api_call }
      format.html { redirect_to account_app_editor_path(@app) }
    end
  end
  
  def destroy
    @api_call.destroy
    
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to account_app_editor_path(@app), notice: "API call log deleted." }
    end
  end
  
  def clear_all
    @app.app_api_calls.destroy_all
    
    respond_to do |format|
      format.json { head :no_content }
      format.html { redirect_to account_app_editor_path(@app), notice: "All API call logs cleared." }
    end
  end
  
  private
  
  def set_api_call
    @api_call = @app.app_api_calls.find(params[:id])
  end
end