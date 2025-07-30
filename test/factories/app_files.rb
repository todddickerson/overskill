FactoryBot.define do
  factory :app_file do
    association :team
    association :app
    path { "index.html" }
    content { "<h1>Hello World</h1>" }
    file_type { "html" }
    size_bytes { content.bytesize }
    checksum { Digest::MD5.hexdigest(content) }
    is_entry_point { path == "index.html" }

    trait :javascript do
      path { "app.js" }
      content { "console.log('Hello from app.js');" }
      file_type { "javascript" }
      is_entry_point { false }
    end

    trait :css do
      path { "styles.css" }
      content { "body { margin: 0; padding: 20px; }" }
      file_type { "css" }
      is_entry_point { false }
    end

    trait :react do
      path { "App.jsx" }
      content { "export default function App() { return <h1>React App</h1>; }" }
      file_type { "javascript" }
      is_entry_point { false }
    end

    trait :large do
      content { "x" * 10000 }
    end
  end
end
