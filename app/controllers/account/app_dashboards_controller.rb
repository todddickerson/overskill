class Account::AppDashboardsController < Account::ApplicationController
  account_load_and_authorize_resource :app, through: :team, through_association: :apps
  
  def show
    # Main dashboard view - handled by app_editors#show with dashboard tab
    redirect_to account_app_editor_path(@app, tab: 'dashboard')
  end
  
  def data
    @tables = @app.app_tables.includes(:app_table_columns)
    
    respond_to do |format|
      format.json { render json: { tables: serialize_tables(@tables) } }
      format.html { render json: { tables: serialize_tables(@tables) } }
    end
  end
  
  def create_table
    @table = @app.app_tables.build(table_params)
    
    if @table.save
      # Create the table in Supabase
      begin
        @table.create_in_supabase!
        render json: { 
          success: true, 
          table: serialize_table(@table),
          message: "Table '#{@table.name}' created successfully"
        }
      rescue => e
        @table.destroy
        render json: { 
          success: false, 
          error: "Failed to create table in database: #{e.message}" 
        }, status: :unprocessable_entity
      end
    else
      render json: { 
        success: false, 
        errors: @table.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end
  
  def update_table
    @table = @app.app_tables.find(params[:table_id])
    
    if @table.update(table_params)
      render json: { 
        success: true, 
        table: serialize_table(@table),
        message: "Table '#{@table.name}' updated successfully"
      }
    else
      render json: { 
        success: false, 
        errors: @table.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end
  
  def delete_table
    @table = @app.app_tables.find(params[:table_id])
    
    begin
      @table.drop_from_supabase!
      @table.destroy
      render json: { 
        success: true, 
        message: "Table '#{@table.name}' deleted successfully"
      }
    rescue => e
      render json: { 
        success: false, 
        error: "Failed to delete table: #{e.message}" 
      }, status: :unprocessable_entity
    end
  end
  
  def table_data
    @table = @app.app_tables.find(params[:table_id])
    
    begin
      service = Supabase::AppDatabaseService.new(@app)
      data = service.get_table_data(@table.name, current_user&.id)
      
      render json: { 
        success: true, 
        data: data,
        columns: @table.schema
      }
    rescue => e
      render json: { 
        success: false, 
        error: "Failed to fetch table data: #{e.message}" 
      }, status: :unprocessable_entity
    end
  end
  
  def create_record
    @table = @app.app_tables.find(params[:table_id])
    
    begin
      service = Supabase::AppDatabaseService.new(@app)
      record = service.insert_record(@table.name, record_params, current_user&.id)
      
      render json: { 
        success: true, 
        record: record,
        message: "Record created successfully"
      }
    rescue => e
      render json: { 
        success: false, 
        error: "Failed to create record: #{e.message}" 
      }, status: :unprocessable_entity
    end
  end
  
  def update_record
    @table = @app.app_tables.find(params[:table_id])
    
    begin
      service = Supabase::AppDatabaseService.new(@app)
      record = service.update_record(@table.name, params[:record_id], record_params, current_user&.id)
      
      render json: { 
        success: true, 
        record: record,
        message: "Record updated successfully"
      }
    rescue => e
      render json: { 
        success: false, 
        error: "Failed to update record: #{e.message}" 
      }, status: :unprocessable_entity
    end
  end
  
  def delete_record
    @table = @app.app_tables.find(params[:table_id])
    
    begin
      service = Supabase::AppDatabaseService.new(@app)
      service.delete_record(@table.name, params[:record_id], current_user&.id)
      
      render json: { 
        success: true,
        message: "Record deleted successfully"
      }
    rescue => e
      render json: { 
        success: false, 
        error: "Failed to delete record: #{e.message}" 
      }, status: :unprocessable_entity
    end
  end
  
  def table_schema
    @table = @app.app_tables.find(params[:table_id])
    
    render json: { 
      success: true, 
      columns: @table.schema,
      table: serialize_table(@table)
    }
  end
  
  def create_column
    @table = @app.app_tables.find(params[:table_id])
    @column = @table.app_table_columns.build(column_params)
    
    if @column.save
      begin
        # Add column to Supabase table
        service = Supabase::AppDatabaseService.new(@app)
        service.add_column(@table.name, @column.name, @column.supabase_type)
        
        render json: { 
          success: true, 
          column: serialize_column(@column),
          message: "Column '#{@column.name}' added successfully"
        }
      rescue => e
        @column.destroy
        render json: { 
          success: false, 
          error: "Failed to add column to database: #{e.message}" 
        }, status: :unprocessable_entity
      end
    else
      render json: { 
        success: false, 
        errors: @column.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end
  
  def update_column
    @table = @app.app_tables.find(params[:table_id])
    @column = @table.app_table_columns.find(params[:column_id])
    
    old_name = @column.name
    old_type = @column.supabase_type
    
    if @column.update(column_params)
      begin
        # Update column in Supabase if name or type changed
        if @column.name != old_name || @column.supabase_type != old_type
          service = Supabase::AppDatabaseService.new(@app)
          service.alter_column(@table.name, old_name, @column.name, @column.supabase_type)
        end
        
        render json: { 
          success: true, 
          column: serialize_column(@column),
          message: "Column '#{@column.name}' updated successfully"
        }
      rescue => e
        # Rollback the change
        @column.update(name: old_name, column_type: old_type)
        render json: { 
          success: false, 
          error: "Failed to update column in database: #{e.message}" 
        }, status: :unprocessable_entity
      end
    else
      render json: { 
        success: false, 
        errors: @column.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end
  
  def delete_column
    @table = @app.app_tables.find(params[:table_id])
    @column = @table.app_table_columns.find(params[:column_id])
    
    column_name = @column.name
    
    begin
      # Remove column from Supabase
      service = Supabase::AppDatabaseService.new(@app)
      service.drop_column(@table.name, @column.name)
      
      @column.destroy
      
      render json: { 
        success: true,
        message: "Column '#{column_name}' deleted successfully"
      }
    rescue => e
      render json: { 
        success: false, 
        error: "Failed to delete column: #{e.message}" 
      }, status: :unprocessable_entity
    end
  end
  
  private
  
  def table_params
    params.require(:table).permit(:name, :description)
  end
  
  def record_params
    params.require(:record).permit!
  end
  
  def column_params
    params.require(:column).permit(:name, :column_type, :required, :default_value, :options)
  end
  
  def serialize_tables(tables)
    tables.map { |table| serialize_table(table) }
  end
  
  def serialize_table(table)
    {
      id: table.id,
      name: table.name,
      description: table.description,
      supabase_table_name: table.supabase_table_name,
      columns: table.schema,
      created_at: table.created_at,
      updated_at: table.updated_at
    }
  end
  
  def serialize_column(column)
    {
      id: column.id,
      name: column.name,
      type: column.column_type,
      required: column.required,
      default: column.default_value,
      options: column.parsed_options,
      created_at: column.created_at,
      updated_at: column.updated_at
    }
  end
end