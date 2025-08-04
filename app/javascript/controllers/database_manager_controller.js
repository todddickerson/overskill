import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tablesContainer", "createTableModal"]
  static values = { appId: String }

  connect() {
    this.loadTables()
  }

  async loadTables() {
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/data`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const data = await response.json()
      
      if (data.tables && data.tables.length > 0) {
        this.renderTables(data.tables)
      } else {
        this.renderEmptyState()
      }
    } catch (error) {
      console.error('Failed to load tables:', error)
      this.renderErrorState()
    }
  }

  renderTables(tables) {
    this.tablesContainerTarget.innerHTML = tables.map(table => `
      <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-6">
        <div class="flex items-center justify-between mb-4">
          <div class="flex items-center">
            <div class="w-10 h-10 bg-blue-100 dark:bg-blue-900 rounded-lg flex items-center justify-center mr-3">
              <i class="fas fa-table text-blue-600 dark:text-blue-400"></i>
            </div>
            <div>
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">${table.name}</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">${table.description || 'No description'}</p>
            </div>
          </div>
          <div class="flex items-center space-x-2">
            <button class="px-3 py-1 text-xs font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded hover:bg-gray-200 dark:hover:bg-gray-600"
                    data-action="click->database-manager#viewTable" 
                    data-table-id="${table.id}"
                    data-table-name="${table.name}">
              <i class="fas fa-eye mr-1"></i>View Data
            </button>
            <button class="px-3 py-1 text-xs font-medium text-blue-700 dark:text-blue-300 bg-blue-100 dark:bg-blue-900 rounded hover:bg-blue-200 dark:hover:bg-blue-800"
                    data-action="click->database-manager#editSchema" 
                    data-table-id="${table.id}"
                    data-table-name="${table.name}">
              <i class="fas fa-edit mr-1"></i>Edit Schema
            </button>
            <button class="px-3 py-1 text-xs font-medium text-red-700 dark:text-red-300 bg-red-100 dark:bg-red-900 rounded hover:bg-red-200 dark:hover:bg-red-800"
                    data-action="click->database-manager#deleteTable" 
                    data-table-id="${table.id}" 
                    data-table-name="${table.name}">
              <i class="fas fa-trash mr-1"></i>Delete
            </button>
          </div>
        </div>
        
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <span class="text-gray-500 dark:text-gray-400">Columns:</span>
            <span class="font-medium text-gray-900 dark:text-white ml-1">${table.columns.length}</span>
          </div>
          <div>
            <span class="text-gray-500 dark:text-gray-400">Supabase Table:</span>
            <span class="font-mono text-xs text-gray-700 dark:text-gray-300 ml-1">${table.supabase_table_name}</span>
          </div>
          <div>
            <span class="text-gray-500 dark:text-gray-400">Created:</span>
            <span class="text-gray-700 dark:text-gray-300 ml-1">${new Date(table.created_at).toLocaleDateString()}</span>
          </div>
          <div>
            <span class="text-gray-500 dark:text-gray-400">Updated:</span>
            <span class="text-gray-700 dark:text-gray-300 ml-1">${new Date(table.updated_at).toLocaleDateString()}</span>
          </div>
        </div>
        
        ${table.columns.length > 0 ? `
          <div class="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
            <h4 class="text-sm font-medium text-gray-900 dark:text-white mb-2">Schema:</h4>
            <div class="flex flex-wrap gap-2">
              ${table.columns.map(col => `
                <span class="inline-flex items-center px-2 py-1 text-xs rounded-full ${this.getColumnTypeClass(col.type)}">
                  <i class="fas fa-${this.getColumnIcon(col.type)} mr-1"></i>
                  ${col.name}: ${col.type}${col.required ? '*' : ''}
                </span>
              `).join('')}
            </div>
          </div>
        ` : ''}
      </div>
    `).join('')
  }

  renderEmptyState() {
    this.tablesContainerTarget.innerHTML = `
      <div class="bg-white dark:bg-gray-800 rounded-lg p-12 border border-gray-200 dark:border-gray-700 text-center">
        <div class="w-16 h-16 bg-gray-100 dark:bg-gray-700 rounded-full flex items-center justify-center mx-auto mb-4">
          <i class="fas fa-database text-gray-400 text-2xl"></i>
        </div>
        <h3 class="text-lg font-semibold text-gray-900 dark:text-white mb-2">No Tables Yet</h3>
        <p class="text-gray-600 dark:text-gray-400 mb-6">Create your first data table to start building your app's database</p>
        <button class="px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700"
                data-action="click->database-manager#showCreateTableModal">
          <i class="fas fa-plus mr-2"></i>Create Your First Table
        </button>
      </div>
    `
  }

  renderErrorState() {
    this.tablesContainerTarget.innerHTML = `
      <div class="bg-red-50 dark:bg-red-900 rounded-lg p-6 border border-red-200 dark:border-red-800 text-center">
        <div class="w-12 h-12 bg-red-100 dark:bg-red-800 rounded-full flex items-center justify-center mx-auto mb-4">
          <i class="fas fa-exclamation-triangle text-red-600 dark:text-red-400"></i>
        </div>
        <h3 class="text-lg font-semibold text-red-900 dark:text-red-100 mb-2">Failed to Load Tables</h3>
        <p class="text-red-700 dark:text-red-300 mb-4">There was an error loading your database tables</p>
        <button class="px-4 py-2 text-sm font-medium text-white bg-red-600 rounded-md hover:bg-red-700"
                data-action="click->database-manager#loadTables">
          <i class="fas fa-refresh mr-2"></i>Try Again
        </button>
      </div>
    `
  }

  showCreateTableModal() {
    this.createTableModalTarget.classList.remove('hidden')
  }

  hideCreateTableModal() {
    this.createTableModalTarget.classList.add('hidden')
    // Reset form
    this.createTableModalTarget.querySelector('form').reset()
  }

  async createTable(event) {
    event.preventDefault()
    
    const formData = new FormData(event.target)
    const tableData = {
      table: {
        name: formData.get('name'),
        description: formData.get('description')
      }
    }

    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/create_table`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify(tableData)
      })

      const result = await response.json()

      if (result.success) {
        this.hideCreateTableModal()
        this.loadTables() // Refresh the tables list
        this.showNotification(result.message, 'success')
      } else {
        this.showNotification(result.error || result.errors?.join(', '), 'error')
      }
    } catch (error) {
      console.error('Failed to create table:', error)
      this.showNotification('Failed to create table. Please try again.', 'error')
    }
  }

  async deleteTable(event) {
    const tableId = event.currentTarget.dataset.tableId
    const tableName = event.currentTarget.dataset.tableName
    
    if (!confirm(`Are you sure you want to delete the table "${tableName}"? This action cannot be undone and will delete all data in the table.`)) {
      return
    }

    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${tableId}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })

      const result = await response.json()

      if (result.success) {
        this.loadTables() // Refresh the tables list
        this.showNotification(result.message, 'success')
      } else {
        this.showNotification(result.error, 'error')
      }
    } catch (error) {
      console.error('Failed to delete table:', error)
      this.showNotification('Failed to delete table. Please try again.', 'error')
    }
  }

  viewTable(event) {
    const tableId = event.currentTarget.dataset.tableId
    const tableName = event.currentTarget.dataset.tableName || 'Table'
    
    // Create and show table data viewer modal
    this.showTableDataViewer(tableId, tableName)
  }
  
  showTableDataViewer(tableId, tableName) {
    const modal = this.createTableDataViewerModal(tableId, tableName)
    document.body.appendChild(modal)
    
    // Initialize the table data viewer controller
    const tableViewer = this.application.getControllerForElementAndIdentifier(modal, 'table-data-viewer')
    if (tableViewer) {
      tableViewer.connect()
    }
  }
  
  createTableDataViewerModal(tableId, tableName) {
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 bg-black bg-opacity-50 z-50'
    modal.setAttribute('data-controller', 'table-data-viewer')
    modal.setAttribute('data-table-data-viewer-app-id-value', this.appIdValue)
    modal.setAttribute('data-table-data-viewer-table-id-value', tableId)
    modal.setAttribute('data-table-data-viewer-table-name-value', tableName)
    
    modal.innerHTML = `
      <div class="flex items-center justify-center min-h-screen p-4">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-7xl max-h-[90vh] overflow-hidden">
          <div class="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
            <div>
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Table Data: ${tableName}</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">View and manage your table records</p>
            </div>
            <div class="flex items-center space-x-3">
              <button class="px-3 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-md hover:bg-gray-200 dark:hover:bg-gray-600"
                      data-action="click->table-data-viewer#refreshData">
                <i class="fas fa-sync-alt mr-2"></i>Refresh
              </button>
              <button class="px-3 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700"
                      data-action="click->table-data-viewer#showAddRecord">
                <i class="fas fa-plus mr-2"></i>Add Record
              </button>
              <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                      onclick="this.closest('.fixed').remove()">
                <i class="fas fa-times text-xl"></i>
              </button>
            </div>
          </div>
          
          <div class="overflow-y-auto max-h-[calc(90vh-120px)]">
            <div data-table-data-viewer-target="tableContainer" class="p-6">
              <!-- Table data will be loaded here -->
              <div class="flex items-center justify-center py-12">
                <div class="w-8 h-8 border-4 border-primary-600 border-t-transparent rounded-full animate-spin"></div>
                <span class="ml-3 text-gray-600 dark:text-gray-400">Loading table data...</span>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Add Record Modal -->
      <div class="fixed inset-0 bg-black bg-opacity-50 hidden z-10" data-table-data-viewer-target="addRecordModal">
        <div class="flex items-center justify-center min-h-screen p-4">
          <div class="bg-white dark:bg-gray-800 rounded-lg p-6 w-full max-w-md max-h-[80vh] overflow-y-auto">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Add New Record</h3>
              <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                      data-action="click->table-data-viewer#hideRecordModals">
                <i class="fas fa-times"></i>
              </button>
            </div>
            
            <form data-table-data-viewer-target="addForm" data-action="submit->table-data-viewer#saveRecord">
              <div id="add-form-fields" class="space-y-4">
                <!-- Form fields will be generated dynamically -->
              </div>
              
              <div class="flex space-x-3 mt-6">
                <button type="button" 
                        class="flex-1 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-md hover:bg-gray-200 dark:hover:bg-gray-600"
                        data-action="click->table-data-viewer#hideRecordModals">
                  Cancel
                </button>
                <button type="submit" 
                        class="flex-1 px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700">
                  Add Record
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
      
      <!-- Edit Record Modal -->
      <div class="fixed inset-0 bg-black bg-opacity-50 hidden z-10" data-table-data-viewer-target="editRecordModal">
        <div class="flex items-center justify-center min-h-screen p-4">
          <div class="bg-white dark:bg-gray-800 rounded-lg p-6 w-full max-w-md max-h-[80vh] overflow-y-auto">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Edit Record</h3>
              <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                      data-action="click->table-data-viewer#hideRecordModals">
                <i class="fas fa-times"></i>
              </button>
            </div>
            
            <form data-table-data-viewer-target="editForm" data-action="submit->table-data-viewer#saveRecord">
              <div id="edit-form-fields" class="space-y-4">
                <!-- Form fields will be generated dynamically -->
              </div>
              
              <div class="flex space-x-3 mt-6">
                <button type="button" 
                        class="flex-1 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-md hover:bg-gray-200 dark:hover:bg-gray-600"
                        data-action="click->table-data-viewer#hideRecordModals">
                  Cancel
                </button>
                <button type="submit" 
                        class="flex-1 px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700">
                  Update Record
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    `
    
    return modal
  }

  editSchema(event) {
    const tableId = event.currentTarget.dataset.tableId
    const tableName = event.currentTarget.dataset.tableName || 'Table'
    
    // Create and show schema editor modal
    this.showSchemaEditor(tableId, tableName)
  }
  
  showSchemaEditor(tableId, tableName) {
    const modal = this.createSchemaEditorModal(tableId, tableName)
    document.body.appendChild(modal)
    
    // Initialize the schema editor controller
    const schemaEditor = this.application.getControllerForElementAndIdentifier(modal, 'schema-editor')
    if (schemaEditor) {
      schemaEditor.connect()
    }
  }
  
  createSchemaEditorModal(tableId, tableName) {
    const modal = document.createElement('div')
    modal.className = 'fixed inset-0 bg-black bg-opacity-50 z-50'
    modal.setAttribute('data-controller', 'schema-editor')
    modal.setAttribute('data-schema-editor-app-id-value', this.appIdValue)
    modal.setAttribute('data-schema-editor-table-id-value', tableId)
    modal.setAttribute('data-schema-editor-table-name-value', tableName)
    
    modal.innerHTML = `
      <div class="flex items-center justify-center min-h-screen p-4">
        <div class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-4xl max-h-[90vh] overflow-hidden">
          <div class="flex items-center justify-between p-6 border-b border-gray-200 dark:border-gray-700">
            <div>
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white">Schema Editor</h3>
              <p class="text-sm text-gray-600 dark:text-gray-400">Manage columns for table: ${tableName}</p>
            </div>
            <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                    onclick="this.closest('.fixed').remove()">
              <i class="fas fa-times text-xl"></i>
            </button>
          </div>
          
          <div class="p-6 overflow-y-auto max-h-[calc(90vh-140px)]">
            <div class="flex items-center justify-between mb-6">
              <div>
                <h4 class="text-md font-medium text-gray-900 dark:text-white">Table Columns</h4>
                <p class="text-sm text-gray-600 dark:text-gray-400">Define the structure of your data</p>
              </div>
              <button class="px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700"
                      data-action="click->schema-editor#addColumn">
                <i class="fas fa-plus mr-2"></i>Add Column
              </button>
            </div>
            
            <div data-schema-editor-target="columnsContainer">
              <!-- Columns will be loaded here -->
            </div>
          </div>
          
          <div class="px-6 py-4 bg-gray-50 dark:bg-gray-700 border-t border-gray-200 dark:border-gray-600">
            <div class="flex justify-end space-x-3">
              <button class="px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-600 border border-gray-300 dark:border-gray-500 rounded-md hover:bg-gray-50 dark:hover:bg-gray-500"
                      onclick="this.closest('.fixed').remove()">
                Close
              </button>
              <button class="px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700"
                      data-action="click->schema-editor#saveSchema">
                <i class="fas fa-save mr-2"></i>Save Schema
              </button>
            </div>
          </div>
        </div>
      </div>
      
      <!-- Column Edit Modal -->
      <div class="fixed inset-0 bg-black bg-opacity-50 hidden z-10" data-schema-editor-target="modal">
        <div class="flex items-center justify-center min-h-screen p-4">
          <div class="bg-white dark:bg-gray-800 rounded-lg p-6 w-full max-w-md">
            <div class="flex items-center justify-between mb-4">
              <h3 class="text-lg font-semibold text-gray-900 dark:text-white" data-form-title>Add New Column</h3>
              <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                      data-action="click->schema-editor#hideModal">
                <i class="fas fa-times"></i>
              </button>
            </div>
            
            <form data-schema-editor-target="form" data-action="submit->schema-editor#saveColumn">
              <div class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Column Name *
                  </label>
                  <input type="text" 
                         name="name" 
                         required
                         pattern="[a-zA-Z][a-zA-Z0-9_]*"
                         class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                         placeholder="e.g., email, name, age">
                  <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    Must start with a letter, contain only letters, numbers, and underscores
                  </p>
                </div>
                
                <div>
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Data Type *
                  </label>
                  <select name="type" 
                          required
                          class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                          data-action="change->schema-editor#handleTypeChange">
                    <option value="text">Text</option>
                    <option value="number">Number</option>
                    <option value="boolean">Boolean (True/False)</option>
                    <option value="date">Date</option>
                    <option value="datetime">Date & Time</option>
                    <option value="select">Select (Single Choice)</option>
                    <option value="multiselect">Multi-Select (Multiple Choices)</option>
                  </select>
                </div>
                
                <div class="hidden" data-options-group>
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Options (one per line)
                  </label>
                  <textarea name="options" 
                            rows="4"
                            class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                            placeholder="Option 1&#10;Option 2&#10;Option 3"></textarea>
                  <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                    Enter each option on a new line
                  </p>
                </div>
                
                <div class="flex items-center">
                  <input type="checkbox" 
                         name="required" 
                         id="required"
                         class="w-4 h-4 text-primary-600 bg-gray-100 border-gray-300 rounded focus:ring-primary-500 dark:focus:ring-primary-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600">
                  <label for="required" class="ml-2 text-sm font-medium text-gray-700 dark:text-gray-300">
                    Required field
                  </label>
                </div>
                
                <div data-default-group>
                  <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Default Value (optional)
                  </label>
                  <input type="text" 
                         name="default_value"
                         class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                         placeholder="Default value">
                </div>
              </div>
              
              <div class="flex space-x-3 mt-6">
                <button type="button" 
                        class="flex-1 px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-gray-100 dark:bg-gray-700 rounded-md hover:bg-gray-200 dark:hover:bg-gray-600"
                        data-action="click->schema-editor#hideModal">
                  Cancel
                </button>
                <button type="submit" 
                        class="flex-1 px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700">
                  Save Column
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>  
    `
    
    return modal
  }

  getColumnTypeClass(type) {
    const classes = {
      'text': 'bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200',
      'number': 'bg-green-100 dark:bg-green-900 text-green-800 dark:text-green-200',
      'boolean': 'bg-purple-100 dark:bg-purple-900 text-purple-800 dark:text-purple-200',
      'date': 'bg-orange-100 dark:bg-orange-900 text-orange-800 dark:text-orange-200',
      'datetime': 'bg-red-100 dark:bg-red-900 text-red-800 dark:text-red-200',
      'select': 'bg-yellow-100 dark:bg-yellow-900 text-yellow-800 dark:text-yellow-200',
      'multiselect': 'bg-indigo-100 dark:bg-indigo-900 text-indigo-800 dark:text-indigo-200'
    }
    return classes[type] || 'bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200'
  }

  getColumnIcon(type) {
    const icons = {
      'text': 'font',
      'number': 'hashtag',
      'boolean': 'toggle-on',
      'date': 'calendar',
      'datetime': 'clock',
      'select': 'list',
      'multiselect': 'list-ul'
    }
    return icons[type] || 'question'
  }

  showNotification(message, type = 'info') {
    // Create a simple notification
    const notification = document.createElement('div')
    notification.className = `fixed top-4 right-4 z-50 px-4 py-3 rounded-md shadow-lg max-w-sm ${
      type === 'success' ? 'bg-green-100 border-green-500 text-green-800' :
      type === 'error' ? 'bg-red-100 border-red-500 text-red-800' :
      'bg-blue-100 border-blue-500 text-blue-800'
    } border-l-4`
    
    notification.innerHTML = `
      <div class="flex items-center">
        <i class="fas fa-${type === 'success' ? 'check' : type === 'error' ? 'exclamation-triangle' : 'info'} mr-2"></i>
        <span>${message}</span>
        <button class="ml-4 text-gray-400 hover:text-gray-600" onclick="this.parentElement.parentElement.remove()">
          <i class="fas fa-times"></i>
        </button>
      </div>
    `
    
    document.body.appendChild(notification)
    
    // Auto-remove after 5 seconds
    setTimeout(() => {
      if (notification.parentElement) {
        notification.remove()
      }
    }, 5000)
  }
}