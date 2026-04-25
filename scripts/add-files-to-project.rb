#!/usr/bin/env ruby
# Add Swift files to the MegaplanHepler Xcode target.
# Usage:
#   GEM_HOME="/opt/homebrew/Cellar/cocoapods/1.16.2_2/libexec" \
#     ruby scripts/add-files-to-project.rb <relative-path> [<relative-path>...]
# Each path is resolved relative to the project root.
# Groups are created on demand to mirror the on-disk path.

require "xcodeproj"

PROJECT_PATH = File.expand_path("../MegaplanHepler.xcodeproj", __dir__)
TARGET_NAME  = "MegaplanHepler"

abort "ERROR: project not found at #{PROJECT_PATH}" unless Dir.exist?(PROJECT_PATH)
abort "ERROR: no files supplied" if ARGV.empty?

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort "ERROR: target '#{TARGET_NAME}' not found" unless target

added = []
skipped = []

ARGV.each do |relative_path|
  abs_path = File.expand_path(relative_path, File.expand_path("..", __dir__))
  unless File.exist?(abs_path)
    abort "ERROR: file does not exist on disk: #{abs_path}"
  end

  # Skip if file already referenced.
  existing_ref = project.files.find { |f| f.real_path.to_s == abs_path }
  if existing_ref
    skipped << relative_path
    next
  end

  # Walk path components and create groups under root group.
  path_parts = relative_path.split(File::SEPARATOR)
  file_name  = path_parts.pop
  parent     = project.main_group

  path_parts.each do |part|
    child = parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == part }
    if child.nil?
      child = parent.new_group(part, part)
    end
    parent = child
  end

  file_ref = parent.new_reference(file_name)
  file_ref.path = file_name

  target.add_file_references([file_ref])

  added << relative_path
end

project.save

puts "Added: #{added.join(', ')}" unless added.empty?
puts "Already present: #{skipped.join(', ')}" unless skipped.empty?
