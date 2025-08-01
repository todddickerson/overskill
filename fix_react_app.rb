# Fix the React app files to be browser-compatible
app = App.find(1)
puts "Fixing React app files for: #{app.name}"

# Update index.html to include React from CDN
index_file = app.app_files.find_by(path: "index.html")
if index_file
  new_content = <<~HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TodoFlow - Beautiful Todo App</title>
  <meta name="description" content="A beautiful and modern todo list application">
  
  <!-- React from CDN -->
  <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
  <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
  
  <!-- Tailwind CSS -->
  <script src="https://cdn.tailwindcss.com"></script>
  
  <!-- Our styles -->
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="root"></div>
  
  <!-- Load our app -->
  <script src="app.js"></script>
</body>
</html>
  HTML
  
  index_file.update!(content: new_content)
  puts "✅ Updated index.html"
end

# Update app.js to use global React (no imports)
app_file = app.app_files.find_by(path: "app.js")
if app_file
  new_content = <<~JS
// TodoFlow App - Browser Compatible Version
const { useState } = React;

function TodoItem({ todo, onToggle, onDelete }) {
  return React.createElement('div', { 
    className: `flex items-center p-3 rounded-lg bg-gray-800 ${todo.completed ? 'opacity-50' : ''}` 
  },
    React.createElement('input', {
      type: 'checkbox',
      checked: todo.completed,
      onChange: () => onToggle(todo.id),
      className: 'mr-3 h-5 w-5 rounded'
    }),
    React.createElement('span', {
      className: `flex-1 ${todo.completed ? 'line-through' : ''}`
    }, todo.text),
    React.createElement('button', {
      onClick: () => onDelete(todo.id),
      className: 'ml-2 text-red-400 hover:text-red-300'
    }, '×')
  );
}

function App() {
  const [todos, setTodos] = useState([]);
  const [inputValue, setInputValue] = useState('');

  const addTodo = (e) => {
    e.preventDefault();
    if (inputValue.trim() === '') return;
    
    const newTodo = { 
      id: Date.now(), 
      text: inputValue.trim(), 
      completed: false 
    };
    
    setTodos([...todos, newTodo]);
    setInputValue('');
  };

  const toggleTodo = (id) => {
    setTodos(todos.map(todo =>
      todo.id === id ? { ...todo, completed: !todo.completed } : todo
    ));
  };

  const deleteTodo = (id) => {
    setTodos(todos.filter(todo => todo.id !== id));
  };

  return React.createElement('div', { className: 'min-h-screen bg-gray-900 text-white' },
    React.createElement('div', { className: 'container mx-auto max-w-2xl p-8' },
      React.createElement('h1', { className: 'text-4xl font-bold mb-8 text-center bg-gradient-to-r from-blue-400 to-purple-500 bg-clip-text text-transparent' }, 
        'TodoFlow'
      ),
      
      // Add todo form
      React.createElement('form', { 
        onSubmit: addTodo,
        className: 'mb-8'
      },
        React.createElement('div', { className: 'flex gap-2' },
          React.createElement('input', {
            type: 'text',
            value: inputValue,
            onChange: (e) => setInputValue(e.target.value),
            placeholder: 'Add a new task...',
            className: 'flex-1 px-4 py-3 rounded-lg bg-gray-800 border border-gray-700 focus:border-blue-500 focus:outline-none'
          }),
          React.createElement('button', {
            type: 'submit',
            className: 'px-6 py-3 bg-blue-500 hover:bg-blue-600 rounded-lg font-semibold transition-colors'
          }, 'Add')
        )
      ),
      
      // Todo list
      React.createElement('div', { className: 'space-y-2' },
        todos.length === 0 
          ? React.createElement('p', { className: 'text-center text-gray-500 py-8' }, 'No tasks yet. Add one above!')
          : todos.map(todo => 
              React.createElement(TodoItem, { 
                key: todo.id, 
                todo: todo, 
                onToggle: toggleTodo,
                onDelete: deleteTodo 
              })
            )
      )
    )
  );
}

// Mount the app
const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(React.createElement(App));
  JS
  
  app_file.update!(content: new_content)
  puts "✅ Updated app.js"
end

# Remove components.js as we've integrated it into app.js
components_file = app.app_files.find_by(path: "components.js")
if components_file
  components_file.destroy
  puts "✅ Removed components.js (integrated into app.js)"
end

# Update styles.css for better visuals
styles_file = app.app_files.find_by(path: "styles.css")
if styles_file
  new_content = <<~CSS
/* TodoFlow Custom Styles */
body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}

* {
  box-sizing: border-box;
}

/* Custom scrollbar */
::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: #1f2937;
}

::-webkit-scrollbar-thumb {
  background: #4b5563;
  border-radius: 4px;
}

::-webkit-scrollbar-thumb:hover {
  background: #6b7280;
}

/* Animations */
@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.animate-fade-in {
  animation: fadeIn 0.3s ease-out;
}
  CSS
  
  styles_file.update!(content: new_content)
  puts "✅ Updated styles.css"
end

# Now update the preview
puts "\n📤 Deploying updated app..."
service = Deployment::CloudflarePreviewService.new(app)
result = service.update_preview!

if result[:success]
  puts "✅ Preview updated successfully!"
  puts "URL: #{app.reload.preview_url}"
else
  puts "❌ Failed to update preview: #{result[:error]}"
end