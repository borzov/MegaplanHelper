#!/usr/bin/env ruby
# Idempotent: adds MegaplanHeplerTests and registers it on the shared scheme.
# Usage: ruby scripts/add-unit-test-target.rb

require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "MegaplanHepler.xcodeproj")
SCHEME_PATH = File.join(PROJECT_PATH, "xcshareddata/xcschemes/MegaplanHepler.xcscheme")
TARGET_NAME = "MegaplanHeplerTests"
APP_NAME = "MegaplanHepler"

project = Xcodeproj::Project.open(PROJECT_PATH)
app = project.targets.find { |t| t.name == APP_NAME }
abort "app target missing" unless app

target = project.targets.find { |t| t.name == TARGET_NAME }
unless target
  target = project.new_target(:unit_test_bundle, TARGET_NAME, :osx, "14.0")
  target.add_dependency(app)
end

# new_target records Cocoa.framework against the SDK directory that is
# installed right now (sourceTree = DEVELOPER_DIR, path under *.sdk/).
# The link is required, so another Xcode fails the test-target link.
# A hosted Swift bundle does not need that framework. Runs on create and
# on later invocations; a later run does not call new_target again.
sdk_pinned = target.frameworks_build_phase.files.filter_map do |build_file|
  ref = build_file.file_ref
  ref if ref&.path.to_s.include?(".sdk/")
end
sdk_pinned.uniq.each(&:remove_from_project)

# Applied on every run. This project stores app settings on the shared
# project configuration, so a new test target inherits Info.plist — including
# NSPrincipalClass. XCTest then allocates a second NSApplication and crashes
# before any test runs.
target.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.ruvents.MegaplanMenuBarAppTests"
  config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "14.0"
  config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
  config.build_settings["INFOPLIST_FILE"] = ""
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = ""
  config.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
  config.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/MegaplanHepler.app/Contents/MacOS/MegaplanHepler"
  config.build_settings["CODE_SIGN_STYLE"] = "Manual"
  config.build_settings["CODE_SIGN_IDENTITY"] = "-"
  config.build_settings["DEVELOPMENT_TEAM"] = ""
  config.build_settings["SWIFT_VERSION"] = "5.9"
end

Dir[File.join(ROOT, "Tests/**/*.swift")].sort.each do |abs|
  next if project.files.any? { |f| f.real_path.to_s == abs }
  rel = abs.delete_prefix(ROOT + "/")
  parts = rel.split("/")
  file_name = parts.pop
  parent = project.main_group
  parts.each do |part|
    child = parent.children.find { |c| c.isa == "PBXGroup" && (c.display_name == part || c.path == part) }
    child = parent.new_group(part, part) if child.nil?
    parent = child
  end
  ref = parent.new_reference(file_name)
  ref.path = file_name
  target.add_file_references([ref])
end

project.save

scheme = Xcodeproj::XCScheme.new(SCHEME_PATH)
already = scheme.test_action.testables.any? { |t| t.buildable_references.any? { |r| r.target_name == TARGET_NAME } }
unless already
  scheme.test_action.add_testable(Xcodeproj::XCScheme::TestAction::TestableReference.new(target))
  scheme.save!
end

puts "Test target ready: #{TARGET_NAME}"
