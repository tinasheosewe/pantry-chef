#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Remove source files (or whole directories) from PantryChef.xcodeproj AND disk.
#
#   ruby tools/xcrm.rb PantryChef/Views PantryChef/App/ContentView.swift
#
# Paths are relative to the directory containing PantryChef.xcodeproj. A directory
# argument removes every file under it. Build-phase entries and now-empty groups
# are cleaned up too.

require "xcodeproj"
require "fileutils"
require "set"

ROOT = File.expand_path("..", __dir__)
project = Xcodeproj::Project.open(File.join(ROOT, "PantryChef.xcodeproj"))
targets = ARGV.map { |p| File.expand_path(p, ROOT) }

def under?(real_path, targets)
  targets.any? { |t| real_path == t || real_path.start_with?(t + File::SEPARATOR) }
end

refs = project.files.select do |ref|
  rp = (ref.real_path.to_s rescue nil)
  rp && under?(rp, targets)
end
ref_set = refs.to_set

project.native_targets.each do |t|
  [t.source_build_phase, t.resources_build_phase, t.frameworks_build_phase].compact.each do |phase|
    phase.files.dup.each do |bf|
      bf.remove_from_project if bf.file_ref && ref_set.include?(bf.file_ref)
    end
  end
end

refs.each(&:remove_from_project)

# Prune groups left empty, deepest first.
project.main_group.recursive_children.select { |c| c.isa == "PBXGroup" }.reverse_each do |g|
  g.remove_from_project if g.children.empty?
end

project.save
targets.each { |t| FileUtils.rm_rf(t) if File.exist?(t) }
puts "Removed #{refs.size} file references; deleted #{targets.size} path(s) from disk."
