import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { versionId: String }

  bookmark(event) {
    event.preventDefault()
    const versionId = this.versionIdValue
    
    // Log for now, will implement actual bookmarking
    console.log("Bookmarking version:", versionId)
    
    // Make request to bookmark endpoint
    fetch(`/account/app_versions/${versionId}/bookmark`, {
      method: 'POST',
      headers: {
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      }
    })
    .then(response => response.json())
    .then(data => {
      if (data.bookmarked) {
        // Update icon to show bookmarked state
        event.currentTarget.classList.add('text-yellow-500')
        event.currentTarget.classList.remove('text-gray-600', 'dark:text-gray-300')
        event.currentTarget.title = 'Remove bookmark'
        
        // Update any bookmark indicators in the header
        const versionHeader = event.currentTarget.closest('.group').querySelector('.fa-bookmark')
        if (!versionHeader) {
          // Add bookmark icon to header
          const timestampSpan = event.currentTarget.closest('.group').querySelector('.text-xs.text-gray-500')
          if (timestampSpan) {
            timestampSpan.insertAdjacentHTML('afterend', ' <i class="fas fa-bookmark text-yellow-500 text-xs" title="Bookmarked"></i>')
          }
        }
      } else {
        // Update icon to show unbookmarked state
        event.currentTarget.classList.remove('text-yellow-500')
        event.currentTarget.classList.add('text-gray-600', 'dark:text-gray-300')
        event.currentTarget.title = 'Bookmark this version'
        
        // Remove bookmark icon from header
        const versionHeader = event.currentTarget.closest('.group').querySelector('.px-4 .fa-bookmark')
        if (versionHeader) {
          versionHeader.remove()
        }
      }
    })
    .catch(error => {
      console.error('Error bookmarking version:', error)
    })
  }
}