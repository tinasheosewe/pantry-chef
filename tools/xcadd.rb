#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Idempotently register source files into PantryChef.xcodeproj.
#
#   ruby tools/xcadd.rb PantryChef/Models/Foo.swift PantryChefTests/FooTests.swift
#
# Files are matched to a target by their top-level directory
# (PantryChefTests* -> test target, else the app target) and placed in the
# Xcode group whose on-disk path matches the file's directory (groups are
# created as needed). Re-running is a no-op for files already present.

require "xcodeproj"

ROOT = File.expand_path("..", __dir__)
PROJECT_PATH = File.join(ROOT, "PantryChef.xcodeproj")

project = Xcodeproj::Project.open(PROJECT_PATH)

def target_named(project, name)
  project.targets.find { |t| t.name == name } or abort("Missing target: #{name}")
end

APP_TARGET  = target_named(project, "PantryChef")
TEST_TARGET = target_named(project, "PantryChefTests")

# Find the group whose real_path is `dir_abs`, creating intermediate groups by
# walking the existing tree from main_group and matching each path segment.
def group_for_dir(project, dir_abs)
  rel = Pathname.new(dir_abs).relative_path_from(Pathname.new(ROOT)).to_s
  group = project.main_group
  rel.split(File::SEPARATOR).each do |seg|
    child = group.children.find do |c|
      c.isa == "PBXGroup" && (c.display_name == seg ||
        (c.real_path.to_s == File.join(group.real_path.to_s, seg) rescue false))
    end
    child ||= group.new_group(seg, seg)
    group = child
  end
  group
end

added = []
present = []

ARGV.each do |rel|
  abs = File.expand_path(rel, ROOT)
  abort("No such file: #{rel}") unless File.exist?(abs)

  top = rel.split(File::SEPARATOR).first
  target = top.start_with?("PantryChefTests") ? TEST_TARGET : APP_TARGET

  group = group_for_dir(project, File.dirname(abs))
  existing = group.files.find { |f| f.real_path.to_s == abs }

  ref = existing || group.new_reference(abs)
  in_phase = target.source_build_phase.files_references.include?(ref)
  target.add_file_references([ref]) unless in_phase

  if existing && in_phase
    present << rel
  else
    added << rel
  end
end

project.save
puts "Added:   #{added.join(', ')}" unless added.empty?
puts "Present: #{present.join(', ')}" unless present.empty?
