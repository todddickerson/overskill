# Fix PurpleTask Pro app to be browser-compatible
app = App.find(18)
puts "Fixing app: #{app.name} (ID: #{app.id})"

# Update app.js to remove imports
app_js = app.app_files.find_by(path: "app.js")
if app_js
  new_content = <<~JS
// PurpleTask Pro - Browser Compatible Version
const { useState, useEffect } = React;

function App() {
  const [tasks, setTasks] = useState(() => {
    const saved = localStorage.getItem('purpletask-tasks');
    return saved ? JSON.parse(saved) : [];
  });
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    localStorage.setItem('purpletask-tasks', JSON.stringify(tasks));
  }, [tasks]);

  const addTask = (task) => {
    setTasks([...tasks, { ...task, id: Date.now() }]);
  };

  const updateTask = (id, updates) => {
    setTasks(tasks.map(task => 
      task.id === id ? { ...task, ...updates } : task
    ));
  };

  const deleteTask = (id) => {
    setTasks(tasks.filter(task => task.id !== id));
  };

  const filteredTasks = tasks.filter(task => {
    if (filter === 'active') return !task.completed;
    if (filter === 'completed') return task.completed;
    return true;
  });

  return React.createElement('div', { className: 'min-h-screen bg-purple-50' },
    React.createElement('div', { className: 'container mx-auto max-w-4xl p-4' },
      React.createElement('header', { className: 'text-center mb-8 pt-8' },
        React.createElement('h1', { className: 'text-5xl font-bold text-purple-800 mb-2' }, 'PurpleTask Pro'),
        React.createElement('p', { className: 'text-purple-600' }, 'Manage your tasks with style')
      ),
      
      React.createElement(TaskForm, { onAddTask: addTask }),
      React.createElement(TaskFilters, { currentFilter: filter, onFilterChange: setFilter }),
      React.createElement(TaskList, { 
        tasks: filteredTasks, 
        onUpdateTask: updateTask,
        onDeleteTask: deleteTask 
      })
    )
  );
}

// Mount the app
const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(React.createElement(App));
  JS
  
  app_js.update!(content: new_content)
  puts "✅ Updated app.js"
end

# Update index.html to load React from CDN
index_file = app.app_files.find_by(path: "index.html")
if index_file
  new_content = <<~HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>PurpleTask Pro - Task Management App</title>
  
  <!-- React from CDN -->
  <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
  <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
  
  <!-- Tailwind CSS -->
  <script src="https://cdn.tailwindcss.com"></script>
  
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <div id="root"></div>
  
  <!-- Load components first, then main app -->
  <script src="components.js"></script>
  <script src="app.js"></script>
</body>
</html>
  HTML
  
  index_file.update!(content: new_content)
  puts "✅ Updated index.html"
end

# Update components.js to be browser-compatible
components_file = app.app_files.find_by(path: "components.js")
if components_file && components_file.content.include?("export")
  # Convert exports to global functions
  new_content = components_file.content
    .gsub(/export function (\w+)/, 'window.\1 = function')
    .gsub(/export const (\w+)/, 'window.\1')
    .gsub(/export \{ [^}]+ \}/, '')
  
  components_file.update!(content: new_content)
  puts "✅ Updated components.js"
end

# Deploy the updated app
puts "\n📤 Deploying updated app..."
service = Deployment::CloudflarePreviewService.new(app)
result = service.update_preview!

if result[:success]
  puts "✅ Deployed successfully!"
  puts "Preview URL: #{app.reload.preview_url}"
else
  puts "❌ Deployment failed: #{result[:error]}"
end