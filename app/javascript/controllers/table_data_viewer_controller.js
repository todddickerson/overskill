import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "tableContainer", "addRecordModal", "editRecordModal", "addForm", "editForm"]
  static values = { 
    appId: String, 
    tableId: String,
    tableName: String
  }

  connect() {
    this.records = []
    this.tableSchema = []
    this.currentEditRecord = null
    this.loadTableData()
  }

  async loadTableData() {
    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/data`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const data = await response.json()
      
      if (data.success) {
        this.records = data.data || []
        this.tableSchema = data.columns || []
        this.renderTable()
      } else {
        this.showNotification(data.error || 'Failed to load table data', 'error')
      }
    } catch (error) {
      console.error('Failed to load table data:', error)
      this.showNotification('Failed to load table data. Please try again.', 'error')
    }
  }

  renderTable() {
    if (this.tableSchema.length === 0) {
      this.renderEmptySchema()
      return
    }

    if (this.records.length === 0) {
      this.renderEmptyTable()
      return
    }

    const tableHTML = `
      <div class="overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
          <thead class="bg-gray-50 dark:bg-gray-800">
            <tr>
              ${this.tableSchema.map(column => `
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                  <div class="flex items-center space-x-1">
                    <span>${column.name}</span>
                    <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${this.getColumnTypeClass(column.type)}">
                      ${column.type}
                    </span>
                    ${column.required ? '<span class="text-red-500">*</span>' : ''}
                  </div>
                </th>
              `).join('')}
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-400 uppercase tracking-wider">
                Actions
              </th>
            </tr>
          </thead>
          <tbody class="bg-white dark:bg-gray-900 divide-y divide-gray-200 dark:divide-gray-700">
            ${this.records.map((record, index) => this.renderTableRow(record, index)).join('')}
          </tbody>
        </table>
      </div>
    `

    this.tableContainerTarget.innerHTML = tableHTML
  }

  renderTableRow(record, index) {
    return `
      <tr class="hover:bg-gray-50 dark:hover:bg-gray-800">
        ${this.tableSchema.map(column => `
          <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 dark:text-white">
            ${this.formatCellValue(record[column.name], column)}
          </td>
        `).join('')}
        <td class="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
          <div class="flex items-center justify-end space-x-2">
            <button class="text-blue-600 hover:text-blue-900 dark:text-blue-400 dark:hover:text-blue-300"
                    data-action="click->table-data-viewer#editRecord"
                    data-record-index="${index}">
              <i class="fas fa-edit"></i>
            </button>
            <button class="text-red-600 hover:text-red-900 dark:text-red-400 dark:hover:text-red-300"
                    data-action="click->table-data-viewer#deleteRecord"
                    data-record-index="${index}">
              <i class="fas fa-trash"></i>
            </button>
          </div>
        </td>
      </tr>
    `
  }

  renderEmptySchema() {
    this.tableContainerTarget.innerHTML = `
      <div class="text-center py-12">
        <div class="w-16 h-16 bg-gray-100 dark:bg-gray-700 rounded-full flex items-center justify-center mx-auto mb-4">
          <i class="fas fa-columns text-gray-400 text-2xl"></i>
        </div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-2">No Schema Defined</h3>
        <p class="text-gray-600 dark:text-gray-400 mb-6">This table doesn't have any columns yet. Define the schema first.</p>
        <button class="px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700"
                onclick="this.closest('.fixed').remove()">
          Close
        </button>
      </div>
    `
  }

  renderEmptyTable() {
    this.tableContainerTarget.innerHTML = `
      <div class="text-center py-12">
        <div class="w-16 h-16 bg-blue-100 dark:bg-blue-900 rounded-full flex items-center justify-center mx-auto mb-4">
          <i class="fas fa-database text-blue-600 dark:text-blue-400 text-2xl"></i>
        </div>
        <h3 class="text-lg font-medium text-gray-900 dark:text-white mb-2">No Data Yet</h3>
        <p class="text-gray-600 dark:text-gray-400 mb-6">This table is empty. Add your first record to get started.</p>
        <button class="px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-md hover:bg-primary-700"
                data-action="click->table-data-viewer#showAddRecord">
          <i class="fas fa-plus mr-2"></i>Add First Record
        </button>
      </div>
    `
  }

  formatCellValue(value, column) {
    if (value === null || value === undefined) {
      return '<span class="text-gray-400 italic">null</span>'
    }

    switch (column.type) {
      case 'boolean':
        return value ? 
          '<span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"><i class="fas fa-check mr-1"></i>True</span>' :
          '<span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200"><i class="fas fa-times mr-1"></i>False</span>'
      
      case 'date':
        return new Date(value).toLocaleDateString()
      
      case 'datetime':
        return new Date(value).toLocaleString()
      
      case 'select':
      case 'multiselect':
        return `<span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">${value}</span>`
        
      default:
        // Truncate long text
        const stringValue = String(value)
        return stringValue.length > 50 ? 
          `<span title="${stringValue}">${stringValue.substring(0, 50)}...</span>` : 
          stringValue
    }
  }

  getColumnTypeClass(type) {
    const classes = {
      'text': 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
      'number': 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
      'boolean': 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200',
      'date': 'bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200',
      'datetime': 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200',
      'select': 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200',
      'multiselect': 'bg-indigo-100 text-indigo-800 dark:bg-indigo-900 dark:text-indigo-200'
    }
    return classes[type] || 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200'
  }

  showAddRecord() {
    this.currentEditRecord = null
    this.populateRecordForm({})
    this.addRecordModalTarget.classList.remove('hidden')
  }

  editRecord(event) {
    const index = parseInt(event.currentTarget.dataset.recordIndex)
    const record = this.records[index]
    
    if (!record) return
    
    this.currentEditRecord = { ...record, index }
    this.populateRecordForm(record)
    this.editRecordModalTarget.classList.remove('hidden')
  }

  populateRecordForm(record) {
    const isEdit = this.currentEditRecord !== null
    const form = isEdit ? this.editFormTarget : this.addFormTarget
    const fieldsContainer = form.querySelector(isEdit ? '#edit-form-fields' : '#add-form-fields')
    
    // Clear form and generate fields
    form.reset()
    this.generateFormFields(fieldsContainer, record)
  }

  generateFormFields(container, record = {}) {
    container.innerHTML = ''
    
    this.tableSchema.forEach(column => {
      const fieldDiv = document.createElement('div')
      const value = record[column.name] || column.default_value || ''
      
      // Label
      const label = document.createElement('label')
      label.className = 'block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2'
      label.textContent = `${column.name}${column.required ? ' *' : ''}`
      fieldDiv.appendChild(label)
      
      // Input field based on column type
      let input
      
      switch (column.type || column.column_type) {
        case 'text':
          input = document.createElement('input')
          input.type = 'text'
          input.value = value
          break
          
        case 'number':
          input = document.createElement('input')
          input.type = 'number'
          input.value = value
          input.step = 'any'
          break
          
        case 'boolean':
          const checkboxDiv = document.createElement('div')
          checkboxDiv.className = 'flex items-center'
          input = document.createElement('input')
          input.type = 'checkbox'
          input.checked = Boolean(value)
          input.className = 'w-4 h-4 text-primary-600 bg-gray-100 border-gray-300 rounded focus:ring-primary-500'
          const checkboxLabel = document.createElement('label')
          checkboxLabel.className = 'ml-2 text-sm text-gray-700 dark:text-gray-300'
          checkboxLabel.textContent = 'Yes'
          checkboxDiv.appendChild(input)
          checkboxDiv.appendChild(checkboxLabel)
          fieldDiv.appendChild(checkboxDiv)
          break
          
        case 'date':
          input = document.createElement('input')
          input.type = 'date'
          if (value) {
            const date = new Date(value)
            input.value = date.toISOString().split('T')[0]
          }
          break
          
        case 'datetime':
          input = document.createElement('input')
          input.type = 'datetime-local'
          if (value) {
            const date = new Date(value)
            input.value = date.toISOString().slice(0, 16)
          }
          break
          
        case 'select':
          input = document.createElement('select')
          input.innerHTML = '<option value="">Select an option</option>'
          
          // Parse options from column metadata
          let options = []
          if (column.options) {
            try {
              const parsed = typeof column.options === 'string' ? JSON.parse(column.options) : column.options
              options = parsed.choices || parsed || []
            } catch (e) {
              console.warn('Could not parse select options:', column.options)
            }
          }
          
          options.forEach(option => {
            const optionEl = document.createElement('option')
            optionEl.value = option
            optionEl.textContent = option
            if (option === value) optionEl.selected = true
            input.appendChild(optionEl)
          })
          break
          
        case 'multiselect':
          input = document.createElement('select')
          input.multiple = true
          input.size = 4
          
          // Parse options from column metadata
          let multioptions = []
          if (column.options) {
            try {
              const parsed = typeof column.options === 'string' ? JSON.parse(column.options) : column.options
              multioptions = parsed.choices || parsed || []
            } catch (e) {
              console.warn('Could not parse multiselect options:', column.options)
            }
          }
          
          const selectedValues = Array.isArray(value) ? value : (value ? value.split(',') : [])
          
          multioptions.forEach(option => {
            const optionEl = document.createElement('option')
            optionEl.value = option
            optionEl.textContent = option
            if (selectedValues.includes(option)) optionEl.selected = true
            input.appendChild(optionEl)
          })
          break
          
        default:
          input = document.createElement('input')
          input.type = 'text'
          input.value = value
      }
      
      if (input && input.type !== 'checkbox') {
        input.name = column.name
        input.className = 'w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-md bg-white dark:bg-gray-700 text-gray-900 dark:text-white'
        if (column.required) {
          input.required = true
        }
        fieldDiv.appendChild(input)
      } else if (input && input.type === 'checkbox') {
        input.name = column.name
        // Checkbox already appended above
      }
      
      container.appendChild(fieldDiv)
    })
  }

  async saveRecord(event) {
    event.preventDefault()
    
    const isEdit = this.currentEditRecord !== null
    const form = event.target
    const formData = new FormData(form)
    
    // Build record data from form
    const recordData = {}
    this.tableSchema.forEach(column => {
      const value = formData.get(column.name)
      
      if (column.type === 'boolean') {
        recordData[column.name] = value === 'on'
      } else if (column.type === 'number') {
        recordData[column.name] = value ? parseFloat(value) : null
      } else {
        recordData[column.name] = value || null
      }
    })

    try {
      let url, method
      if (isEdit) {
        method = 'PATCH'
        url = `/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/records/${this.currentEditRecord.id}`
      } else {
        method = 'POST'
        url = `/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/records`
      }
      
      const response = await fetch(url, {
        method: method,
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        },
        body: JSON.stringify({ record: recordData })
      })
      
      const result = await response.json()
      
      if (result.success) {
        this.hideRecordModals()
        this.loadTableData() // Refresh table data
        this.showNotification(
          isEdit ? 'Record updated successfully' : 'Record added successfully',
          'success'
        )
      } else {
        this.showNotification(result.error || 'Failed to save record', 'error')
      }
      
    } catch (error) {
      console.error('Failed to save record:', error)
      this.showNotification('Failed to save record. Please try again.', 'error')
    }
  }

  async deleteRecord(event) {
    const index = parseInt(event.currentTarget.dataset.recordIndex)
    const record = this.records[index]
    
    if (!record) return
    
    if (!confirm('Are you sure you want to delete this record? This action cannot be undone.')) {
      return
    }

    try {
      const response = await fetch(`/account/apps/${this.appIdValue}/dashboard/tables/${this.tableIdValue}/records/${record.id}`, {
        method: 'DELETE',
        headers: {
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      })
      
      const result = await response.json()
      
      if (result.success) {
        this.loadTableData() // Refresh table data
        this.showNotification('Record deleted successfully', 'success')
      } else {
        this.showNotification(result.error || 'Failed to delete record', 'error')
      }
      
    } catch (error) {
      console.error('Failed to delete record:', error)
      this.showNotification('Failed to delete record. Please try again.', 'error')
    }
  }

  hideRecordModals() {
    this.addRecordModalTarget.classList.add('hidden')
    this.editRecordModalTarget.classList.add('hidden')
    this.currentEditRecord = null
  }

  refreshData() {
    this.loadTableData()
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