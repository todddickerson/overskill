import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "form", "columnsContainer", "columnTemplate"]
  static values = { 
    appId: String, 
    tableId: String,
    tableName: String
  }

  connect() {
    this.columns = []
    this.loadTableSchema()
  }

  async loadTableSchema() {
    if (!this.tableIdValue) {
      this.renderEmptySchema()
      return
    }

    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/schema`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.columns = data.columns || []
        this.renderSchema()
      } else {
        this.showNotification('Failed to load table schema', 'error')
      }
    } catch (error) {
      console.error('Failed to load schema:', error)
      this.renderEmptySchema()
    }
  }

  renderSchema() {
    this.columnsContainerTarget.innerHTML = this.columns.map((column, index) => 
      this.renderColumnRow(column, index)
    ).join('')
  }

  renderEmptySchema() {
    this.columnsContainerTarget.innerHTML = `
      <div class="text-center py-8 text-gray-500 dark:text-gray-400">
        <i class="fas fa-columns text-3xl mb-4"></i>
        <p class="text-lg font-medium mb-2">No columns defined</p>
        <p class="text-sm">Add your first column to start building your table schema</p>
      </div>
    `
  }

  renderColumnRow(column, index) {
    const typeClass = this.getColumnTypeClass(column.type)
    const typeIcon = this.getColumnTypeIcon(column.type)
    
    return `
      <div class="bg-white dark:bg-gray-800 rounded-lg border border-gray-200 dark:border-gray-700 p-4 mb-3" data-column-index="${index}">
        <div class="flex items-center justify-between">
          <div class="flex items-center flex-1">
            <div class="w-10 h-10 ${typeClass} rounded-lg flex items-center justify-center mr-4">
              <i class="fas fa-${typeIcon}"></i>
            </div>
            <div class="flex-1">
              <div class="flex items-center space-x-4">
                <div>
                  <h4 class="text-sm font-semibold text-gray-900 dark:text-white">${column.name}</h4>
                  <p class="text-xs text-gray-500 dark:text-gray-400">${column.type}${column.required ? ' • Required' : ''}</p>
                </div>
                ${column.default ? `
                  <div class="text-xs">
                    <span class="text-gray-500 dark:text-gray-400">Default:</span>
                    <span class="font-mono text-gray-700 dark:text-gray-300">${column.default}</span>
                  </div>
                ` : ''}
                ${column.options && Object.keys(column.options).length > 0 ? `
                  <div class="text-xs">
                    <span class="text-gray-500 dark:text-gray-400">Options:</span>
                    <span class="font-mono text-gray-700 dark:text-gray-300">${JSON.stringify(column.options)}</span>
                  </div>
                ` : ''}
              </div>
            </div>
          </div>
          <div class="flex items-center space-x-2 ml-4">
            <button class="px-3 py-1 text-xs font-medium text-blue-700 dark:text-blue-300 bg-blue-100 dark:bg-blue-900 rounded hover:bg-blue-200 dark:hover:bg-blue-800"
                    data-action="click->schema-editor#editColumn" 
                    data-column-index="${index}">
              <i class="fas fa-edit mr-1"></i>Edit
            </button>
            <button class="px-3 py-1 text-xs font-medium text-red-700 dark:text-red-300 bg-red-100 dark:bg-red-900 rounded hover:bg-red-200 dark:hover:bg-red-800"
                    data-action="click->schema-editor#deleteColumn" 
                    data-column-index="${index}"
                    data-column-name="${column.name}">
              <i class="fas fa-trash mr-1"></i>Delete
            </button>
          </div>
        </div>
      </div>
    `
  }

  showModal() {
    this.modalTarget.classList.remove('hidden')
    this.resetForm()
  }

  hideModal() {
    this.modalTarget.classList.add('hidden')
    this.resetForm()
  }

  resetForm() {
    this.formTarget.reset()
    this.currentEditIndex = null
    this.updateFormTitle()
    this.toggleAdvancedOptions(false)
  }

  updateFormTitle() {
    const title = this.modalTarget.querySelector('[data-form-title]')
    if (title) {
      title.textContent = this.currentEditIndex !== null ? 'Edit Column' : 'Add New Column'
    }
  }

  addColumn() {
    this.currentEditIndex = null
    this.showModal()
  }

  editColumn(event) {
    const index = parseInt(event.currentTarget.dataset.columnIndex)
    const column = this.columns[index]
    
    if (!column) return
    
    this.currentEditIndex = index
    this.populateForm(column)
    this.showModal()
  }

  populateForm(column) {
    const form = this.formTarget
    form.querySelector('[name="name"]').value = column.name || ''
    form.querySelector('[name="type"]').value = column.type || 'text'
    form.querySelector('[name="required"]').checked = column.required || false
    form.querySelector('[name="default_value"]').value = column.default || ''
    
    // Handle options for select/multiselect
    if (column.type === 'select' || column.type === 'multiselect') {
      const optionsField = form.querySelector('[name="options"]')
      if (optionsField && column.options && column.options.choices) {
        optionsField.value = column.options.choices.join('\n')
      }
    }
    
    this.updateFormTitle()
    this.toggleAdvancedOptions(true)
    this.handleTypeChange() // Update form based on type
  }

  async saveColumn(event) {
    event.preventDefault()
    
    const formData = new FormData(this.formTarget)
    const columnData = {
      name: formData.get('name'),
      type: formData.get('type'),
      required: formData.get('required') === 'on',
      default_value: formData.get('default_value') || null
    }
    
    // Handle options for select types
    if (columnData.type === 'select' || columnData.type === 'multiselect') {
      const optionsText = formData.get('options') || ''
      const choices = optionsText.split('\n').map(s => s.trim()).filter(s => s.length > 0)
      columnData.options = { choices }
    }
    
    try {
      let url, method
      if (this.currentEditIndex !== null) {
        // Update existing column
        this.columns[this.currentEditIndex] = columnData
        method = 'PATCH'
        url = `/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/columns/${this.currentEditIndex}`
      } else {
        // Add new column
        this.columns.push(columnData)
        method = 'POST'
        url = `/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/columns`
      }
      
      const response = await fetch(url, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ column: columnData })
      })
      
      const result = await response.json()
      
      if (result.success) {
        this.hideModal()
        this.renderSchema()
        this.showNotification(
          this.currentEditIndex !== null ? 'Column updated successfully' : 'Column added successfully',
          'success'
        )
      } else {
        this.showNotification(result.error || 'Failed to save column', 'error')
      }
      
    } catch (error) {
      console.error('Failed to save column:', error)
      this.showNotification('Failed to save column. Please try again.', 'error')
    }
  }

  async deleteColumn(event) {
    const index = parseInt(event.currentTarget.dataset.columnIndex)
    const columnName = event.currentTarget.dataset.columnName
    
    if (!confirm(`Are you sure you want to delete the column "${columnName}"? This will permanently remove the column and all its data.`)) {
      return
    }
    
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/columns/${index}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const result = await response.json()
      
      if (result.success) {
        this.columns.splice(index, 1)
        this.renderSchema()
        this.showNotification('Column deleted successfully', 'success')
      } else {
        this.showNotification(result.error || 'Failed to delete column', 'error')
      }
      
    } catch (error) {
      console.error('Failed to delete column:', error)
      this.showNotification('Failed to delete column. Please try again.', 'error')
    }
  }

  handleTypeChange(event) {
    const type = event ? event.target.value : this.formTarget.querySelector('[name="type"]').value
    const optionsGroup = this.formTarget.querySelector('[data-options-group]')
    const defaultGroup = this.formTarget.querySelector('[data-default-group]')
    
    // Show/hide options field for select types
    if (optionsGroup) {
      if (type === 'select' || type === 'multiselect') {
        optionsGroup.classList.remove('hidden')
      } else {
        optionsGroup.classList.add('hidden')
      }
    }
    
    // Update default value placeholder based on type
    const defaultInput = this.formTarget.querySelector('[name="default_value"]')
    if (defaultInput) {
      const placeholders = {
        'text': 'e.g., Default text',
        'number': 'e.g., 42',
        'boolean': 'true or false',
        'date': 'YYYY-MM-DD',
        'datetime': 'YYYY-MM-DD HH:MM:SS',
        'select': 'One of the options above',
        'multiselect': 'Comma-separated options'
      }
      defaultInput.placeholder = placeholders[type] || 'Default value'
    }
  }

  toggleAdvancedOptions(show = null) {
    const advancedSection = this.formTarget.querySelector('[data-advanced-options]')
    if (advancedSection) {
      if (show === null) {
        advancedSection.classList.toggle('hidden')
      } else if (show) {
        advancedSection.classList.remove('hidden')
      } else {
        advancedSection.classList.add('hidden')
      }
    }
  }

  getColumnTypeClass(type) {
    const classes = {
      'text': 'bg-blue-100 dark:bg-blue-900 text-blue-600 dark:text-blue-400',
      'number': 'bg-green-100 dark:bg-green-900 text-green-600 dark:text-green-400',
      'boolean': 'bg-purple-100 dark:bg-purple-900 text-purple-600 dark:text-purple-400',
      'date': 'bg-orange-100 dark:bg-orange-900 text-orange-600 dark:text-orange-400',
      'datetime': 'bg-red-100 dark:bg-red-900 text-red-600 dark:text-red-400',
      'select': 'bg-yellow-100 dark:bg-yellow-900 text-yellow-600 dark:text-yellow-400',
      'multiselect': 'bg-indigo-100 dark:bg-indigo-900 text-indigo-600 dark:text-indigo-400'
    }
    return classes[type] || 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400'
  }

  getColumnTypeIcon(type) {
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