#!/usr/bin/env ruby
# Create a fresh todo app with user-scoped lists and items
# Run with: bin/rails runner scripts/create_todo_app_fresh.rb

puts "🚀 Creating fresh todo app with user scoping..."
puts "=" * 80

# Create the app
team = Team.first
timestamp = Time.now.to_i
app = team.apps.create!(
  name: "TodoMaster Pro #{timestamp}",
  slug: "todo-master-#{timestamp}",
  prompt: "Create a comprehensive todo list app with user authentication, multiple lists per user, and full CRUD operations for todo items",
  creator: team.memberships.first,
  base_price: 0,
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "✅ Created app: ##{app.id} - #{app.name}"

# Generate auth files with enhanced OAuth
puts "\n📝 Generating enhanced authentication system..."
auth_files = Ai::AuthTemplates.generate_auth_files(app)

auth_files.each do |file|
  app.app_files.create!(path: file[:path], content: file[:content])
  puts "  ✅ #{file[:path]}"
end

# Create database schema for user-scoped todos
puts "\n🗄️ Setting up database schema..."

# Create todos table
todos_schema = {
  name: "todos",
  description: "User todo lists with items",
  columns: [
    {
      name: "id",
      type: "text",
      primary_key: true,
      default_value: "gen_random_uuid()"
    },
    {
      name: "user_id",
      type: "text",
      required: true,
      description: "Foreign key to auth.users"
    },
    {
      name: "title",
      type: "text",
      required: true,
      description: "Todo list title"
    },
    {
      name: "description",
      type: "text",
      description: "Optional list description"
    },
    {
      name: "color",
      type: "text",
      default_value: "#3b82f6",
      description: "List color theme"
    },
    {
      name: "created_at",
      type: "datetime",
      default_value: "now()"
    },
    {
      name: "updated_at",
      type: "datetime",
      default_value: "now()"
    }
  ]
}

# Create todo_items table
items_schema = {
  name: "todo_items",
  description: "Individual todo items within lists",
  columns: [
    {
      name: "id",
      type: "text",
      primary_key: true,
      default_value: "gen_random_uuid()"
    },
    {
      name: "todo_id",
      type: "text",
      required: true,
      description: "Foreign key to todos table"
    },
    {
      name: "title",
      type: "text",
      required: true,
      description: "Todo item title"
    },
    {
      name: "description",
      type: "text",
      description: "Optional item description"
    },
    {
      name: "completed",
      type: "boolean",
      default_value: false
    },
    {
      name: "priority",
      type: "text",
      default_value: "medium",
      description: "Priority: low, medium, high"
    },
    {
      name: "due_date",
      type: "datetime",
      description: "Optional due date"
    },
    {
      name: "created_at",
      type: "datetime",
      default_value: "now()"
    },
    {
      name: "updated_at",
      type: "datetime",
      default_value: "now()"
    }
  ]
}

# Create the database tables
supabase_service = Supabase::AppDatabaseService.new(app)

todos_result = supabase_service.create_table(todos_schema[:name], todos_schema[:columns])
if todos_result[:success]
  puts "  ✅ Created todos table"
  app.app_tables.create!(
    name: todos_schema[:name],
    description: todos_schema[:description],
    schema_json: todos_schema[:columns]
  )
else
  puts "  ❌ Failed to create todos table: #{todos_result[:error]}"
end

items_result = supabase_service.create_table(items_schema[:name], items_schema[:columns])
if items_result[:success]
  puts "  ✅ Created todo_items table"
  app.app_tables.create!(
    name: items_schema[:name],
    description: items_schema[:description],
    schema_json: items_schema[:columns]
  )
else
  puts "  ❌ Failed to create todo_items table: #{items_result[:error]}"
end

# Generate the React application files
puts "\n⚛️ Generating React application files..."

# Main App component
main_app_content = <<~TSX
  import React from 'react'
  import ReactDOM from 'react-dom/client'
  import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
  import { AuthProvider } from './contexts/AuthContext'
  import { Login } from './pages/auth/Login'
  import { Signup } from './pages/auth/Signup'
  import { AuthCallback } from './pages/auth/AuthCallback'
  import { Dashboard } from './pages/Dashboard'
  import { TodoList } from './pages/TodoList'
  import { ProtectedRoute } from './components/auth/ProtectedRoute'
  import './index.css'
  
  ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
      <AuthProvider>
        <BrowserRouter>
          <Routes>
            <Route path="/" element={<Navigate to="/dashboard" replace />} />
            <Route path="/login" element={<Login />} />
            <Route path="/signup" element={<Signup />} />
            <Route path="/auth/callback" element={<AuthCallback />} />
            <Route path="/dashboard" element={
              <ProtectedRoute>
                <Dashboard />
              </ProtectedRoute>
            } />
            <Route path="/todos/:id" element={
              <ProtectedRoute>
                <TodoList />
              </ProtectedRoute>
            } />
          </Routes>
        </BrowserRouter>
      </AuthProvider>
    </React.StrictMode>,
  )
TSX

# Dashboard component
dashboard_content = <<~TSX
  import { useState, useEffect } from 'react'
  import { Link } from 'react-router-dom'
  import { useAuth } from '../hooks/useAuth'
  import { supabase } from '../lib/supabase'
  import { PlusIcon, ListBulletIcon } from '@heroicons/react/24/outline'
  
  interface TodoList {
    id: string
    title: string
    description?: string
    color: string
    created_at: string
    item_count?: number
    completed_count?: number
  }
  
  export function Dashboard() {
    const { user } = useAuth()
    const [lists, setLists] = useState<TodoList[]>([])
    const [loading, setLoading] = useState(true)
    const [showNewList, setShowNewList] = useState(false)
    const [newListTitle, setNewListTitle] = useState('')
    const [newListDescription, setNewListDescription] = useState('')
    const [newListColor, setNewListColor] = useState('#3b82f6')
  
    useEffect(() => {
      if (user) {
        fetchLists()
      }
    }, [user])
  
    const fetchLists = async () => {
      try {
        const { data: listsData, error } = await supabase
          .from('app_${app.id}_todos')
          .select('*')
          .eq('user_id', user!.id)
          .order('created_at', { ascending: false })
  
        if (error) throw error
  
        // Fetch item counts for each list
        const listsWithCounts = await Promise.all(
          (listsData || []).map(async (list) => {
            const { data: items } = await supabase
              .from('app_${app.id}_todo_items')
              .select('id, completed')
              .eq('todo_id', list.id)
  
            const item_count = items?.length || 0
            const completed_count = items?.filter(item => item.completed).length || 0
  
            return { ...list, item_count, completed_count }
          })
        )
  
        setLists(listsWithCounts)
      } catch (error) {
        console.error('Error fetching lists:', error)
      } finally {
        setLoading(false)
      }
    }
  
    const createList = async (e: React.FormEvent) => {
      e.preventDefault()
      if (!newListTitle.trim()) return
  
      try {
        const { error } = await supabase
          .from('app_${app.id}_todos')
          .insert({
            user_id: user!.id,
            title: newListTitle.trim(),
            description: newListDescription.trim() || null,
            color: newListColor
          })
  
        if (error) throw error
  
        setNewListTitle('')
        setNewListDescription('')
        setNewListColor('#3b82f6')
        setShowNewList(false)
        fetchLists()
      } catch (error) {
        console.error('Error creating list:', error)
        alert('Failed to create list. Please try again.')
      }
    }
  
    const deleteList = async (listId: string) => {
      if (!confirm('Are you sure you want to delete this list and all its items?')) return
  
      try {
        // Delete all items first
        await supabase
          .from('app_${app.id}_todo_items')
          .delete()
          .eq('todo_id', listId)
  
        // Then delete the list
        const { error } = await supabase
          .from('app_${app.id}_todos')
          .delete()
          .eq('id', listId)
          .eq('user_id', user!.id)
  
        if (error) throw error
  
        fetchLists()
      } catch (error) {
        console.error('Error deleting list:', error)
        alert('Failed to delete list. Please try again.')
      }
    }
  
    const handleSignOut = async () => {
      await supabase.auth.signOut()
      window.location.href = '/login'
    }
  
    if (loading) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        </div>
      )
    }
  
    return (
      <div className="min-h-screen bg-gray-50">
        <div className="bg-white shadow-sm border-b">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="flex justify-between items-center py-6">
              <div>
                <h1 className="text-2xl font-bold text-gray-900">TodoMaster Pro</h1>
                <p className="text-sm text-gray-600">Welcome back, {user?.email}</p>
              </div>
              <div className="flex items-center space-x-4">
                <button
                  onClick={() => setShowNewList(true)}
                  className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 flex items-center"
                >
                  <PlusIcon className="h-4 w-4 mr-2" />
                  New List
                </button>
                <button
                  onClick={handleSignOut}
                  className="text-gray-600 hover:text-gray-800"
                >
                  Sign Out
                </button>
              </div>
            </div>
          </div>
        </div>
  
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {showNewList && (
            <div className="bg-white rounded-lg shadow-md p-6 mb-8">
              <h2 className="text-lg font-medium text-gray-900 mb-4">Create New List</h2>
              <form onSubmit={createList} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Title</label>
                  <input
                    type="text"
                    value={newListTitle}
                    onChange={(e) => setNewListTitle(e.target.value)}
                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    placeholder="Enter list title"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700">Description (optional)</label>
                  <textarea
                    value={newListDescription}
                    onChange={(e) => setNewListDescription(e.target.value)}
                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    rows={3}
                    placeholder="Enter list description"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700">Color</label>
                  <div className="mt-1 flex space-x-2">
                    {['#3b82f6', '#ef4444', '#10b981', '#f59e0b', '#8b5cf6', '#ec4899'].map(color => (
                      <button
                        key={color}
                        type="button"
                        onClick={() => setNewListColor(color)}
                        className={`w-8 h-8 rounded-full border-2 ${color === newListColor ? 'border-gray-800' : 'border-gray-300'}`}
                        style={{ backgroundColor: color }}
                      />
                    ))}
                  </div>
                </div>
                <div className="flex justify-end space-x-3">
                  <button
                    type="button"
                    onClick={() => setShowNewList(false)}
                    className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
                  >
                    Create List
                  </button>
                </div>
              </form>
            </div>
          )}
  
          {lists.length === 0 ? (
            <div className="text-center py-12">
              <ListBulletIcon className="mx-auto h-12 w-12 text-gray-400" />
              <h3 className="mt-2 text-sm font-medium text-gray-900">No todo lists</h3>
              <p className="mt-1 text-sm text-gray-500">Get started by creating your first list.</p>
              <div className="mt-6">
                <button
                  onClick={() => setShowNewList(true)}
                  className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700"
                >
                  Create List
                </button>
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {lists.map((list) => (
                <div key={list.id} className="bg-white rounded-lg shadow-md hover:shadow-lg transition-shadow">
                  <div className="p-6">
                    <div className="flex items-center justify-between mb-4">
                      <div 
                        className="w-4 h-4 rounded-full"
                        style={{ backgroundColor: list.color }}
                      />
                      <button
                        onClick={() => deleteList(list.id)}
                        className="text-gray-400 hover:text-red-600 text-sm"
                      >
                        Delete
                      </button>
                    </div>
                    <h3 className="text-lg font-medium text-gray-900 mb-2">{list.title}</h3>
                    {list.description && (
                      <p className="text-sm text-gray-600 mb-4">{list.description}</p>
                    )}
                    <div className="flex justify-between items-center text-sm text-gray-500 mb-4">
                      <span>{list.item_count || 0} items</span>
                      <span>{list.completed_count || 0} completed</span>
                    </div>
                    <Link
                      to={`/todos/${list.id}`}
                      className="block w-full text-center bg-blue-50 text-blue-700 px-4 py-2 rounded-md hover:bg-blue-100 transition-colors"
                    >
                      Open List
                    </Link>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    )
  }
TSX

# TodoList component
todolist_content = <<~TSX
  import { useState, useEffect } from 'react'
  import { useParams, Link } from 'react-router-dom'
  import { useAuth } from '../hooks/useAuth'
  import { supabase } from '../lib/supabase'
  import { ArrowLeftIcon, PlusIcon, CheckIcon, XMarkIcon } from '@heroicons/react/24/outline'
  
  interface TodoList {
    id: string
    title: string
    description?: string
    color: string
  }
  
  interface TodoItem {
    id: string
    todo_id: string
    title: string
    description?: string
    completed: boolean
    priority: 'low' | 'medium' | 'high'
    due_date?: string
    created_at: string
  }
  
  export function TodoList() {
    const { id } = useParams<{ id: string }>()
    const { user } = useAuth()
    const [list, setList] = useState<TodoList | null>(null)
    const [items, setItems] = useState<TodoItem[]>([])
    const [loading, setLoading] = useState(true)
    const [showNewItem, setShowNewItem] = useState(false)
    const [newItemTitle, setNewItemTitle] = useState('')
    const [newItemDescription, setNewItemDescription] = useState('')
    const [newItemPriority, setNewItemPriority] = useState<'low' | 'medium' | 'high'>('medium')
    const [newItemDueDate, setNewItemDueDate] = useState('')
  
    useEffect(() => {
      if (user && id) {
        fetchListAndItems()
      }
    }, [user, id])
  
    const fetchListAndItems = async () => {
      try {
        // Fetch list details
        const { data: listData, error: listError } = await supabase
          .from('app_${app.id}_todos')
          .select('*')
          .eq('id', id)
          .eq('user_id', user!.id)
          .single()
  
        if (listError) throw listError
        setList(listData)
  
        // Fetch items
        const { data: itemsData, error: itemsError } = await supabase
          .from('app_${app.id}_todo_items')
          .select('*')
          .eq('todo_id', id)
          .order('created_at', { ascending: false })
  
        if (itemsError) throw itemsError
        setItems(itemsData || [])
      } catch (error) {
        console.error('Error fetching data:', error)
      } finally {
        setLoading(false)
      }
    }
  
    const createItem = async (e: React.FormEvent) => {
      e.preventDefault()
      if (!newItemTitle.trim()) return
  
      try {
        const { error } = await supabase
          .from('app_${app.id}_todo_items')
          .insert({
            todo_id: id,
            title: newItemTitle.trim(),
            description: newItemDescription.trim() || null,
            priority: newItemPriority,
            due_date: newItemDueDate || null,
            completed: false
          })
  
        if (error) throw error
  
        setNewItemTitle('')
        setNewItemDescription('')
        setNewItemPriority('medium')
        setNewItemDueDate('')
        setShowNewItem(false)
        fetchListAndItems()
      } catch (error) {
        console.error('Error creating item:', error)
        alert('Failed to create item. Please try again.')
      }
    }
  
    const toggleItemComplete = async (itemId: string, completed: boolean) => {
      try {
        const { error } = await supabase
          .from('app_${app.id}_todo_items')
          .update({ completed })
          .eq('id', itemId)
  
        if (error) throw error
  
        setItems(items.map(item => 
          item.id === itemId ? { ...item, completed } : item
        ))
      } catch (error) {
        console.error('Error updating item:', error)
        alert('Failed to update item. Please try again.')
      }
    }
  
    const deleteItem = async (itemId: string) => {
      if (!confirm('Are you sure you want to delete this item?')) return
  
      try {
        const { error } = await supabase
          .from('app_${app.id}_todo_items')
          .delete()
          .eq('id', itemId)
  
        if (error) throw error
  
        setItems(items.filter(item => item.id !== itemId))
      } catch (error) {
        console.error('Error deleting item:', error)
        alert('Failed to delete item. Please try again.')
      }
    }
  
    const getPriorityColor = (priority: string) => {
      switch (priority) {
        case 'high': return 'text-red-600 bg-red-50'
        case 'medium': return 'text-yellow-600 bg-yellow-50'
        case 'low': return 'text-green-600 bg-green-50'
        default: return 'text-gray-600 bg-gray-50'
      }
    }
  
    if (loading) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        </div>
      )
    }
  
    if (!list) {
      return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50">
          <div className="text-center">
            <h2 className="text-lg font-medium text-gray-900">List not found</h2>
            <Link to="/dashboard" className="text-blue-600 hover:text-blue-800">
              Back to Dashboard
            </Link>
          </div>
        </div>
      )
    }
  
    const completedItems = items.filter(item => item.completed)
    const pendingItems = items.filter(item => !item.completed)
  
    return (
      <div className="min-h-screen bg-gray-50">
        <div className="bg-white shadow-sm border-b">
          <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
            <div className="flex items-center justify-between py-6">
              <div className="flex items-center">
                <Link 
                  to="/dashboard"
                  className="mr-4 text-gray-600 hover:text-gray-800"
                >
                  <ArrowLeftIcon className="h-5 w-5" />
                </Link>
                <div className="flex items-center">
                  <div 
                    className="w-4 h-4 rounded-full mr-3"
                    style={{ backgroundColor: list.color }}
                  />
                  <div>
                    <h1 className="text-2xl font-bold text-gray-900">{list.title}</h1>
                    {list.description && (
                      <p className="text-sm text-gray-600">{list.description}</p>
                    )}
                  </div>
                </div>
              </div>
              <button
                onClick={() => setShowNewItem(true)}
                className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 flex items-center"
              >
                <PlusIcon className="h-4 w-4 mr-2" />
                Add Item
              </button>
            </div>
          </div>
        </div>
  
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          {showNewItem && (
            <div className="bg-white rounded-lg shadow-md p-6 mb-8">
              <h2 className="text-lg font-medium text-gray-900 mb-4">Add New Item</h2>
              <form onSubmit={createItem} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700">Title</label>
                  <input
                    type="text"
                    value={newItemTitle}
                    onChange={(e) => setNewItemTitle(e.target.value)}
                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    placeholder="Enter item title"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700">Description (optional)</label>
                  <textarea
                    value={newItemDescription}
                    onChange={(e) => setNewItemDescription(e.target.value)}
                    className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    rows={3}
                    placeholder="Enter item description"
                  />
                </div>
                <div className="flex space-x-4">
                  <div className="flex-1">
                    <label className="block text-sm font-medium text-gray-700">Priority</label>
                    <select
                      value={newItemPriority}
                      onChange={(e) => setNewItemPriority(e.target.value as 'low' | 'medium' | 'high')}
                      className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    >
                      <option value="low">Low</option>
                      <option value="medium">Medium</option>
                      <option value="high">High</option>
                    </select>
                  </div>
                  <div className="flex-1">
                    <label className="block text-sm font-medium text-gray-700">Due Date (optional)</label>
                    <input
                      type="date"
                      value={newItemDueDate}
                      onChange={(e) => setNewItemDueDate(e.target.value)}
                      className="mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                    />
                  </div>
                </div>
                <div className="flex justify-end space-x-3">
                  <button
                    type="button"
                    onClick={() => setShowNewItem(false)}
                    className="px-4 py-2 text-sm font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    className="px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
                  >
                    Add Item
                  </button>
                </div>
              </form>
            </div>
          )}
  
          <div className="space-y-6">
            {/* Pending Items */}
            <div>
              <h2 className="text-lg font-medium text-gray-900 mb-4">
                Pending ({pendingItems.length})
              </h2>
              <div className="space-y-3">
                {pendingItems.map((item) => (
                  <div key={item.id} className="bg-white rounded-lg shadow-sm border p-4 hover:shadow-md transition-shadow">
                    <div className="flex items-start justify-between">
                      <div className="flex items-start space-x-3 flex-1">
                        <button
                          onClick={() => toggleItemComplete(item.id, true)}
                          className="mt-1 text-gray-400 hover:text-green-600"
                        >
                          <div className="w-5 h-5 border-2 border-gray-300 rounded hover:border-green-600"></div>
                        </button>
                        <div className="flex-1">
                          <h3 className="text-sm font-medium text-gray-900">{item.title}</h3>
                          {item.description && (
                            <p className="text-sm text-gray-600 mt-1">{item.description}</p>
                          )}
                          <div className="flex items-center space-x-3 mt-2">
                            <span className={`px-2 py-1 text-xs rounded-full ${getPriorityColor(item.priority)}`}>
                              {item.priority}
                            </span>
                            {item.due_date && (
                              <span className="text-xs text-gray-500">
                                Due: {new Date(item.due_date).toLocaleDateString()}
                              </span>
                            )}
                          </div>
                        </div>
                      </div>
                      <button
                        onClick={() => deleteItem(item.id)}
                        className="text-gray-400 hover:text-red-600"
                      >
                        <XMarkIcon className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                ))}
                {pendingItems.length === 0 && (
                  <p className="text-gray-500 text-center py-8">No pending items</p>
                )}
              </div>
            </div>
  
            {/* Completed Items */}
            {completedItems.length > 0 && (
              <div>
                <h2 className="text-lg font-medium text-gray-900 mb-4">
                  Completed ({completedItems.length})
                </h2>
                <div className="space-y-3">
                  {completedItems.map((item) => (
                    <div key={item.id} className="bg-gray-50 rounded-lg border p-4">
                      <div className="flex items-start justify-between">
                        <div className="flex items-start space-x-3 flex-1">
                          <button
                            onClick={() => toggleItemComplete(item.id, false)}
                            className="mt-1 text-green-600 hover:text-gray-400"
                          >
                            <CheckIcon className="w-5 h-5" />
                          </button>
                          <div className="flex-1">
                            <h3 className="text-sm font-medium text-gray-500 line-through">{item.title}</h3>
                            {item.description && (
                              <p className="text-sm text-gray-400 mt-1 line-through">{item.description}</p>
                            )}
                          </div>
                        </div>
                        <button
                          onClick={() => deleteItem(item.id)}
                          className="text-gray-400 hover:text-red-600"
                        >
                          <XMarkIcon className="h-4 w-4" />
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    )
  }
TSX

# Additional required files
index_html = <<~HTML
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>TodoMaster Pro</title>
    <script src="https://cdn.tailwindcss.com"></script>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
  </html>
HTML

css_content = <<~CSS
  @tailwind base;
  @tailwind components;
  @tailwind utilities;
  
  /* Custom styles */
  .animate-spin {
    animation: spin 1s linear infinite;
  }
  
  @keyframes spin {
    from {
      transform: rotate(0deg);
    }
    to {
      transform: rotate(360deg);
    }
  }
CSS

# Create all app files
files_to_create = [
  {path: "index.html", content: index_html},
  {path: "src/main.tsx", content: main_app_content},
  {path: "src/pages/Dashboard.tsx", content: dashboard_content},
  {path: "src/pages/TodoList.tsx", content: todolist_content},
  {path: "src/index.css", content: css_content}
]

puts "\n📄 Creating application files..."
files_to_create.each do |file|
  app.app_files.create!(path: file[:path], content: file[:content])
  puts "  ✅ #{file[:path]}"
end

# Deploy the application
puts "\n🚀 Deploying TodoMaster Pro..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  app.update!(status: "generated", preview_url: result[:preview_url])
  puts "✅ Deployment successful!"
  puts "🌐 App URL: #{result[:preview_url]}"

  puts "\n📋 TodoMaster Pro Features:"
  puts "  ✅ User authentication with enhanced OAuth"
  puts "  ✅ User-scoped todo lists"
  puts "  ✅ Full CRUD operations for lists and items"
  puts "  ✅ Priority levels (low, medium, high)"
  puts "  ✅ Due dates for items"
  puts "  ✅ Color-coded lists"
  puts "  ✅ Item completion tracking"
  puts "  ✅ Responsive design"

  puts "\n🧪 Ready for testing!"
  puts "  1. Visit: #{result[:preview_url]}/login"
  puts "  2. Sign up or login with OAuth"
  puts "  3. Create todo lists"
  puts "  4. Add items with priorities and due dates"
  puts "  5. Mark items as complete"

  puts "\nApp ID: #{app.id} for Playwright testing"
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n" + "=" * 80
puts "TodoMaster Pro creation complete!"
puts "=" * 80
