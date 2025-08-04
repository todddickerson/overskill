# Supabase Integration Guide for OverSkill

**CRITICAL DOCUMENTATION** - This system enables Base44-style database management for OverSkill apps.

## Overview

OverSkill uses Supabase as the backend database for all generated apps, providing:
- **App-specific database isolation** with row-level security
- **Dynamic schema management** for each app
- **Real-time CRUD operations** through the dashboard
- **Secure multi-tenant architecture** with proper data isolation

## Architecture

### Database Structure
```
Supabase Database
├── app_1 (schema)
│   ├── users (table)
│   ├── posts (table)
│   └── comments (table)
├── app_2 (schema)
│   ├── products (table)
│   └── orders (table)
└── app_N (schema)
    └── [dynamic tables]
```

### Row-Level Security (RLS)
Each app gets its own schema with RLS policies that ensure:
- Users can only access data from their own app
- Team members can collaborate on the same app data
- Complete isolation between different apps

## Key Components

### 1. Models

#### AppTable (`app/models/app_table.rb`)
- Represents a database table within an app
- Maps to actual Supabase tables
- Validates table names and structure

```ruby
class AppTable < ApplicationRecord
  belongs_to :app
  has_many :app_table_columns, dependent: :destroy
  
  def supabase_table_name
    "app_#{app.id}_#{name}"
  end
  
  def create_in_supabase!
    Supabase::AppDatabaseService.new(app).create_table(name, schema)
  end
end
```

#### AppTableColumn (`app/models/app_table_column.rb`)
- Defines column schema for app tables
- Supports: text, number, boolean, date, datetime, select, multiselect

### 2. Service Layer

#### Supabase::AppDatabaseService (`app/services/supabase/app_database_service.rb`)
**CRITICAL SERVICE** - Handles all Supabase operations:

```ruby
class Supabase::AppDatabaseService
  def initialize(app)
    @app = app
  end
  
  # Core methods:
  def create_app_database        # Creates app-specific schema
  def create_table(name, schema) # Creates table with RLS
  def get_table_data(table_name) # Fetches data with security
  def insert_record(table, data) # Inserts with user context
  def update_record(table, id, data) # Updates with RLS
  def delete_record(table, id)   # Deletes with RLS
end
```

### 3. Controller Layer

#### Account::AppDashboardsController (`app/controllers/account/app_dashboards_controller.rb`)
Provides RESTful API for dashboard operations:

```ruby
# Routes:
GET    /account/apps/:app_id/dashboard/data
POST   /account/apps/:app_id/dashboard/create_table
PATCH  /account/apps/:app_id/dashboard/tables/:table_id
DELETE /account/apps/:app_id/dashboard/tables/:table_id
GET    /account/apps/:app_id/dashboard/tables/:table_id/data
POST   /account/apps/:app_id/dashboard/tables/:table_id/records
PATCH  /account/apps/:app_id/dashboard/tables/:table_id/records/:record_id
DELETE /account/apps/:app_id/dashboard/tables/:table_id/records/:record_id
```

### 4. Frontend Layer

#### Dashboard Interface (`app/views/account/app_editors/_dashboard_panel.html.erb`)
- Base44-style database management UI
- Integrated into app editor as "Dashboard" tab
- Modal-based table creation and management

#### Stimulus Controller (`app/javascript/controllers/database_manager_controller.js`)
- Handles all client-side database operations
- Real-time table loading and management
- Form handling for table creation
- Notification system for user feedback

## Environment Configuration

Required environment variables:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
SUPABASE_SERVICE_KEY=your-service-key
```

## Security Model

### App Isolation
1. Each app gets its own PostgreSQL schema: `app_#{app.id}`
2. Tables are prefixed: `app_#{app.id}_#{table_name}`
3. RLS policies ensure user can only access their app's data

### User Context
- Every record includes `app_user_id` for RLS
- Policies check user permissions via `user_has_access()` function
- Team membership determines access rights

### SQL Security Functions
```sql
-- Created for each app schema
CREATE FUNCTION app_123.user_has_access(user_id TEXT, requesting_app_user_id TEXT)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN user_id = requesting_app_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

## Usage Flow

### 1. Creating a Table
1. User clicks "Create Table" in dashboard
2. Modal opens with table name/description form
3. Frontend submits to `POST /dashboard/create_table`
4. Controller creates `AppTable` record
5. Service creates actual Supabase table with RLS
6. Frontend refreshes table list

### 2. Managing Data
1. User clicks "View Data" on existing table
2. Frontend fetches data via `GET /tables/:id/data`
3. Service queries Supabase with RLS context
4. Data displayed in dashboard interface
5. CRUD operations update both Rails and Supabase

## API Response Format

### Tables List
```json
{
  "tables": [
    {
      "id": 1,
      "name": "users",
      "description": "App user accounts",
      "supabase_table_name": "app_123_users",
      "columns": [
        {
          "name": "email",
          "type": "text",
          "required": true,
          "default": null,
          "options": {}
        }
      ],
      "created_at": "2025-08-04T15:00:00Z",
      "updated_at": "2025-08-04T15:00:00Z"
    }
  ]
}
```

### Error Handling
```json
{
  "success": false,
  "error": "Failed to create table in database: permission denied"
}
```

## Testing Strategy

### Unit Tests
- Model validations and relationships
- Service layer Supabase integration
- Controller API responses

### Integration Tests
- End-to-end table creation flow
- RLS policy enforcement
- Multi-app data isolation

### System Tests
- Dashboard UI interactions
- Modal functionality
- Real-time updates

## Deployment Considerations

1. **Supabase Setup**: Ensure Supabase project is configured with proper RLS
2. **Environment Variables**: All Supabase credentials must be set
3. **Database Migrations**: Run Rails migrations for AppTable models
4. **Feature Flags**: Consider gradual rollout of database features

## Monitoring and Maintenance

### Key Metrics
- Table creation success rate
- Query performance by app
- RLS policy effectiveness
- User adoption of database features

### Troubleshooting
- Check Supabase logs for RLS violations
- Monitor Rails logs for service errors
- Verify environment variable configuration
- Test API endpoints directly

## Future Enhancements

1. **Schema Editor**: Visual column management interface
2. **Data Import/Export**: CSV and JSON data handling
3. **Relationships**: Foreign key support between tables
4. **Indexing**: Performance optimization tools
5. **Analytics**: Query performance insights

## Critical Notes

⚠️ **IMPORTANT**: This integration is fundamental to OverSkill's competitive advantage over Base44 and Lovable. The real-time, instant deployment capability combined with professional database management positions us uniquely in the market.

🔒 **SECURITY**: RLS policies are critical - any changes must be thoroughly tested to ensure data isolation between apps.

🚀 **PERFORMANCE**: Monitor Supabase usage limits and consider optimization as user base grows.

This documentation should be kept up-to-date as the system evolves. All team members working on database features must understand this architecture.