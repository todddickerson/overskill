#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(238)
pkg = app.app_files.find_by(path: 'package.json')
content = JSON.parse(pkg.content)

puts "Fixing package.json dependencies..."
content['dependencies'].each do |dep, version|
  if version.include?('latest')
    old_version = version
    new_version = version.gsub('^latest', 'latest')
    content['dependencies'][dep] = new_version
    puts "  #{dep}: #{old_version} -> #{new_version}"
  end
end

pkg.update!(content: JSON.pretty_generate(content))
puts "Updated package.json"