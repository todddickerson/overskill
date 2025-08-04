import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["canvas", "toolbar", "properties", "tableTemplate", "connectionLine"]
  static values = { 
    appId: Number,
    tables: Array
  }
  
  connect() {
    this.tables = new Map()
    this.connections = []
    this.selectedTable = null
    this.isDragging = false
    this.draggedTable = null
    this.connectionStart = null
    
    this.initializeCanvas()
    this.loadExistingTables()
    this.setupEventListeners()
  }
  
  initializeCanvas() {
    // Set up the canvas/grid background
    this.canvasTarget.style.backgroundImage = `
      linear-gradient(rgba(0,0,0,0.05) 1px, transparent 1px),
      linear-gradient(90deg, rgba(0,0,0,0.05) 1px, transparent 1px)
    `
    this.canvasTarget.style.backgroundSize = '20px 20px'
  }
  
  loadExistingTables() {
    // Load tables from the database
    fetch(`/account/apps/${this.appIdValue}/dashboard/data.json`)
      .then(response => response.json())
      .then(data => {
        if (data.tables) {
          data.tables.forEach(table => this.addTableToCanvas(table))
        }
      })
  }
  
  setupEventListeners() {
    // Canvas click to deselect
    this.canvasTarget.addEventListener('click', (e) => {
      if (e.target === this.canvasTarget) {
        this.deselectAll()
      }
    })
    
    // Prevent text selection while dragging
    this.canvasTarget.addEventListener('selectstart', (e) => {
      if (this.isDragging) e.preventDefault()
    })
  }
  
  // Create new table
  createTable(event) {
    event.preventDefault()
    
    const tableName = prompt('Enter table name:')
    if (!tableName) return
    
    // Create table via API
    fetch(`/account/apps/${this.appIdValue}/dashboard/tables`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        table: {
          name: tableName,
          description: ''
        }
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.addTableToCanvas(data.table)
      } else {
        alert(data.error || 'Failed to create table')
      }
    })
  }
  
  addTableToCanvas(tableData) {
    const table = this.createTableElement(tableData)
    const position = this.findEmptyPosition()
    
    table.style.left = position.x + 'px'
    table.style.top = position.y + 'px'
    
    this.canvasTarget.appendChild(table)
    this.tables.set(tableData.id, {
      element: table,
      data: tableData,
      position: position
    })
    
    this.updateConnections()
  }
  
  createTableElement(tableData) {
    const table = document.createElement('div')
    table.className = 'absolute bg-white dark:bg-gray-800 rounded-lg shadow-lg border-2 border-gray-200 dark:border-gray-700 cursor-move select-none'
    table.style.width = '250px'
    table.dataset.tableId = tableData.id
    
    // Header
    const header = document.createElement('div')
    header.className = 'px-4 py-3 bg-gray-50 dark:bg-gray-900 rounded-t-lg border-b border-gray-200 dark:border-gray-700'
    header.innerHTML = `
      <div class="flex items-center justify-between">
        <h3 class="font-semibold text-gray-900 dark:text-white">${tableData.name}</h3>
        <button class="text-gray-400 hover:text-gray-600 dark:hover:text-gray-300" data-action="click->database-schema-editor#deleteTable">
          <i class="fas fa-times text-xs"></i>
        </button>
      </div>
    `
    
    // Columns
    const columns = document.createElement('div')
    columns.className = 'p-3 space-y-1'
    
    // Add ID column (always present)
    columns.appendChild(this.createColumnElement({
      name: 'id',
      type: 'uuid',
      isPrimary: true
    }))
    
    // Add other columns
    if (tableData.columns) {
      tableData.columns.forEach(col => {
        if (col.name !== 'id') {
          columns.appendChild(this.createColumnElement(col))
        }
      })
    }
    
    // Add column button
    const addButton = document.createElement('button')
    addButton.className = 'w-full mt-2 px-3 py-1 text-xs text-gray-600 dark:text-gray-400 hover:text-gray-900 dark:hover:text-white border border-dashed border-gray-300 dark:border-gray-600 rounded hover:border-gray-400 dark:hover:border-gray-500'
    addButton.innerHTML = '<i class="fas fa-plus mr-1"></i> Add Column'
    addButton.dataset.action = 'click->database-schema-editor#addColumn'
    columns.appendChild(addButton)
    
    table.appendChild(header)
    table.appendChild(columns)
    
    // Make draggable
    this.makeDraggable(table)
    
    // Click to select
    table.addEventListener('click', (e) => {
      e.stopPropagation()
      this.selectTable(table, tableData)
    })
    
    return table
  }
  
  createColumnElement(column) {
    const col = document.createElement('div')
    col.className = 'flex items-center justify-between text-sm py-1 px-2 rounded hover:bg-gray-50 dark:hover:bg-gray-700'
    
    const icon = column.isPrimary ? 'fa-key text-yellow-500' : 
                 column.isForeign ? 'fa-link text-blue-500' : 
                 'fa-columns text-gray-400'
    
    col.innerHTML = `
      <div class="flex items-center space-x-2">
        <i class="fas ${icon} text-xs"></i>
        <span class="text-gray-900 dark:text-white">${column.name}</span>
      </div>
      <span class="text-gray-500 dark:text-gray-400 text-xs">${column.type}</span>
    `
    
    return col
  }
  
  makeDraggable(element) {
    let startX, startY, initialX, initialY
    
    const mouseDown = (e) => {
      if (e.target.closest('button')) return
      
      this.isDragging = true
      this.draggedTable = element
      
      startX = e.clientX
      startY = e.clientY
      
      const rect = element.getBoundingClientRect()
      const canvasRect = this.canvasTarget.getBoundingClientRect()
      
      initialX = rect.left - canvasRect.left
      initialY = rect.top - canvasRect.top
      
      element.style.zIndex = '1000'
      element.classList.add('shadow-2xl')
      
      document.addEventListener('mousemove', mouseMove)
      document.addEventListener('mouseup', mouseUp)
    }
    
    const mouseMove = (e) => {
      if (!this.isDragging) return
      
      const dx = e.clientX - startX
      const dy = e.clientY - startY
      
      element.style.left = (initialX + dx) + 'px'
      element.style.top = (initialY + dy) + 'px'
      
      this.updateConnections()
    }
    
    const mouseUp = () => {
      this.isDragging = false
      this.draggedTable = null
      
      element.style.zIndex = ''
      element.classList.remove('shadow-2xl')
      
      // Update position in storage
      const tableId = element.dataset.tableId
      const table = this.tables.get(parseInt(tableId))
      if (table) {
        table.position = {
          x: parseInt(element.style.left),
          y: parseInt(element.style.top)
        }
      }
      
      document.removeEventListener('mousemove', mouseMove)
      document.removeEventListener('mouseup', mouseUp)
    }
    
    element.addEventListener('mousedown', mouseDown)
  }
  
  selectTable(element, tableData) {
    this.deselectAll()
    
    element.classList.add('border-blue-500', 'dark:border-blue-400')
    element.classList.remove('border-gray-200', 'dark:border-gray-700')
    
    this.selectedTable = tableData
    this.showProperties(tableData)
  }
  
  deselectAll() {
    this.tables.forEach(table => {
      table.element.classList.remove('border-blue-500', 'dark:border-blue-400')
      table.element.classList.add('border-gray-200', 'dark:border-gray-700')
    })
    
    this.selectedTable = null
    this.hideProperties()
  }
  
  showProperties(tableData) {
    if (!this.hasPropertiesTarget) return
    
    this.propertiesTarget.innerHTML = `
      <div class="p-4">
        <h3 class="font-semibold text-gray-900 dark:text-white mb-4">Table Properties</h3>
        
        <div class="space-y-4">
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Table Name
            </label>
            <input type="text" 
                   value="${tableData.name}" 
                   class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                   readonly>
          </div>
          
          <div>
            <label class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Description
            </label>
            <textarea rows="3" 
                      class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white"
                      placeholder="Add a description...">${tableData.description || ''}</textarea>
          </div>
          
          <div>
            <h4 class="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Columns</h4>
            <div class="space-y-2">
              ${this.renderColumnsList(tableData.columns || [])}
            </div>
          </div>
        </div>
      </div>
    `
    
    this.propertiesTarget.classList.remove('hidden')
  }
  
  hideProperties() {
    if (this.hasPropertiesTarget) {
      this.propertiesTarget.classList.add('hidden')
    }
  }
  
  renderColumnsList(columns) {
    return columns.map(col => `
      <div class="flex items-center justify-between p-2 bg-gray-50 dark:bg-gray-800 rounded">
        <div>
          <span class="text-sm font-medium text-gray-900 dark:text-white">${col.name}</span>
          <span class="text-xs text-gray-500 dark:text-gray-400 ml-2">${col.type}</span>
        </div>
        <button class="text-gray-400 hover:text-red-600 dark:hover:text-red-400">
          <i class="fas fa-trash-alt text-xs"></i>
        </button>
      </div>
    `).join('')
  }
  
  findEmptyPosition() {
    // Find a position that doesn't overlap with existing tables
    let x = 50
    let y = 50
    const spacing = 300
    
    // Simple grid placement
    const positions = Array.from(this.tables.values()).map(t => t.position)
    
    while (positions.some(p => Math.abs(p.x - x) < 250 && Math.abs(p.y - y) < 150)) {
      x += spacing
      if (x > 800) {
        x = 50
        y += 200
      }
    }
    
    return { x, y }
  }
  
  updateConnections() {
    // This would draw connection lines between related tables
    // For now, just a placeholder
  }
  
  deleteTable(event) {
    event.stopPropagation()
    
    if (!confirm('Are you sure you want to delete this table?')) return
    
    const tableElement = event.target.closest('[data-table-id]')
    const tableId = parseInt(tableElement.dataset.tableId)
    
    fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${tableId}`, {
      method: 'DELETE',
      headers: {
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        tableElement.remove()
        this.tables.delete(tableId)
        this.deselectAll()
      } else {
        alert(data.error || 'Failed to delete table')
      }
    })
  }
  
  addColumn(event) {
    event.stopPropagation()
    
    const tableElement = event.target.closest('[data-table-id]')
    const tableId = parseInt(tableElement.dataset.tableId)
    
    const columnName = prompt('Enter column name:')
    if (!columnName) return
    
    const columnType = prompt('Enter column type (text, integer, boolean, timestamp):')
    if (!columnType) return
    
    fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${tableId}/columns`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        column: {
          name: columnName,
          column_type: columnType
        }
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Reload the table to show new column
        location.reload()
      } else {
        alert(data.error || 'Failed to add column')
      }
    })
  }
  
  // Helper methods for creating common tables
  createUsersTable(event) {
    event.preventDefault()
    
    this.createTableWithSchema({
      name: 'users',
      description: 'User accounts for your application',
      columns: [
        { name: 'email', type: 'text', required: true },
        { name: 'name', type: 'text' },
        { name: 'avatar_url', type: 'text' },
        { name: 'created_at', type: 'timestamp' },
        { name: 'updated_at', type: 'timestamp' }
      ]
    })
  }
  
  createPostsTable(event) {
    event.preventDefault()
    
    this.createTableWithSchema({
      name: 'posts',
      description: 'Blog posts or articles',
      columns: [
        { name: 'title', type: 'text', required: true },
        { name: 'content', type: 'text' },
        { name: 'user_id', type: 'uuid', isForeign: true },
        { name: 'published', type: 'boolean', default: false },
        { name: 'published_at', type: 'timestamp' },
        { name: 'created_at', type: 'timestamp' },
        { name: 'updated_at', type: 'timestamp' }
      ]
    })
  }
  
  createCommentsTable(event) {
    event.preventDefault()
    
    this.createTableWithSchema({
      name: 'comments',
      description: 'User comments on posts',
      columns: [
        { name: 'content', type: 'text', required: true },
        { name: 'post_id', type: 'uuid', isForeign: true },
        { name: 'user_id', type: 'uuid', isForeign: true },
        { name: 'created_at', type: 'timestamp' },
        { name: 'updated_at', type: 'timestamp' }
      ]
    })
  }
  
  createTableWithSchema(schema) {
    // Create table with predefined schema
    fetch(`/account/apps/${this.appIdValue}/dashboard/tables`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        table: {
          name: schema.name,
          description: schema.description
        }
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.addTableToCanvas(data.table)
        
        // Add columns one by one
        schema.columns.forEach((col, index) => {
          setTimeout(() => {
            this.addColumnToTable(data.table.id, col)
          }, index * 500) // Stagger the requests
        })
      } else {
        alert(data.error || 'Failed to create table')
      }
    })
  }
  
  addColumnToTable(tableId, columnDef) {
    fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${tableId}/columns`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        column: {
          name: columnDef.name,
          column_type: columnDef.type,
          required: columnDef.required || false,
          default_value: columnDef.default
        }
      })
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Update the visual representation
        const table = this.tables.get(tableId)
        if (table) {
          const colElement = this.createColumnElement({
            ...columnDef,
            name: data.column.name,
            type: data.column.type
          })
          
          const columnsContainer = table.element.querySelector('.space-y-1')
          const addButton = columnsContainer.querySelector('button[data-action*="addColumn"]')
          columnsContainer.insertBefore(colElement, addButton)
        }
      }
    })
  }
}