import { useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'

interface DropzoneProps {
  bucketName?: string
  onUploadComplete?: (urls: string[]) => void
  maxSize?: number // in bytes
  accept?: string[] // MIME types
}

export function Dropzone({ 
  bucketName = 'uploads', 
  onUploadComplete,
  maxSize = 10 * 1024 * 1024, // 10MB default
  accept = ['image/*', 'application/pdf']
}: DropzoneProps) {
  const [isDragging, setIsDragging] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [uploadedFiles, setUploadedFiles] = useState<string[]>([])
  const [error, setError] = useState<string | null>(null)

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
    
    const files = Array.from(e.dataTransfer.files)
    handleFiles(files)
  }, [])

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files ? Array.from(e.target.files) : []
    handleFiles(files)
  }

  const handleFiles = async (files: File[]) => {
    setError(null)
    setUploading(true)
    
    try {
      // Validate files
      for (const file of files) {
        if (file.size > maxSize) {
          throw new Error(`File ${file.name} exceeds maximum size of ${formatBytes(maxSize)}`)
        }
        
        if (accept.length > 0) {
          const isAccepted = accept.some(type => {
            if (type.endsWith('/*')) {
              const category = type.split('/')[0]
              return file.type.startsWith(category + '/')
            }
            return file.type === type
          })
          
          if (!isAccepted) {
            throw new Error(`File type ${file.type} is not accepted`)
          }
        }
      }

      // Upload files
      const uploadPromises = files.map(async (file) => {
        const fileExt = file.name.split('.').pop()
        const fileName = `${Math.random().toString(36).substring(2)}.${fileExt}`
        const filePath = `${bucketName}/${fileName}`

        const { error: uploadError, data } = await supabase.storage
          .from(bucketName)
          .upload(filePath, file)

        if (uploadError) throw uploadError

        // Get public URL
        const { data: { publicUrl } } = supabase.storage
          .from(bucketName)
          .getPublicUrl(filePath)

        return publicUrl
      })

      const urls = await Promise.all(uploadPromises)
      setUploadedFiles(prev => [...prev, ...urls])
      onUploadComplete?.(urls)
      
    } catch (error: any) {
      setError(error.message || 'Upload failed')
    } finally {
      setUploading(false)
    }
  }

  const formatBytes = (bytes: number) => {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
  }

  return (
    <div className="w-full">
      <div
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
        className={`relative border-2 border-dashed rounded-lg p-8 text-center transition-colors ${
          isDragging 
            ? 'border-blue-500 bg-blue-50' 
            : 'border-gray-300 hover:border-gray-400'
        } ${uploading ? 'opacity-50 pointer-events-none' : ''}`}
      >
        <input
          type="file"
          multiple
          onChange={handleFileSelect}
          accept={accept.join(',')}
          className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
          disabled={uploading}
        />
        
        <div className="space-y-4">
          <div className="flex justify-center">
            <svg className="w-12 h-12 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" />
            </svg>
          </div>
          
          <div>
            <p className="text-lg font-medium text-gray-900">
              {uploading ? 'Uploading...' : 'Drop files here or click to upload'}
            </p>
            <p className="text-sm text-gray-500 mt-1">
              Maximum file size: {formatBytes(maxSize)}
            </p>
          </div>
        </div>
      </div>

      {error && (
        <div className="mt-4 p-3 bg-red-50 border border-red-200 rounded-md">
          <p className="text-sm text-red-800">{error}</p>
        </div>
      )}

      {uploadedFiles.length > 0 && (
        <div className="mt-6">
          <h4 className="text-sm font-medium text-gray-900 mb-2">Uploaded Files:</h4>
          <ul className="space-y-2">
            {uploadedFiles.map((url, index) => (
              <li key={index} className="flex items-center text-sm text-gray-600">
                <svg className="w-4 h-4 text-green-500 mr-2" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
                <a href={url} target="_blank" rel="noopener noreferrer" className="hover:text-blue-600 truncate">
                  {url.split('/').pop()}
                </a>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}