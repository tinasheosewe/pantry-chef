#!/usr/bin/env ruby
# One-shot: create the Share extension target, wire its Info.plist/entitlements, share
# the two core files (SharedRecipeInbox, ShareItemExtractor) into it, give the app the
# App-Group entitlement, and embed the extension in the app. Idempotent-ish: bails if the
# target already exists.
require "xcodeproj"

proj = Xcodeproj::Project.open("PantryChef.xcodeproj")
app  = proj.targets.find { |t| t.name == "PantryChef" }
raise "app target not found" unless app
if proj.targets.any? { |t| t.name == "ShareExtension" }
  abort "ShareExtension target already exists — nothing to do."
end

TEAM = "WZ7SK754J9"

# 1. The extension target.
ext = proj.new_target(:app_extension, "ShareExtension", :ios, "17.0")
ext.build_configurations.each do |c|
  c.build_settings.merge!(
    "PRODUCT_BUNDLE_IDENTIFIER" => "com.tboya.pantrychef.PantryChef.ShareExtension",
    "INFOPLIST_FILE"            => "ShareExtension/Info.plist",
    "CODE_SIGN_ENTITLEMENTS"    => "ShareExtension/ShareExtension.entitlements",
    "CODE_SIGN_STYLE"           => "Automatic",
    "DEVELOPMENT_TEAM"          => TEAM,
    "IPHONEOS_DEPLOYMENT_TARGET"=> "17.0",
    "SWIFT_VERSION"             => "5.9",
    "GENERATE_INFOPLIST_FILE"   => "NO",
    "PRODUCT_NAME"              => "$(TARGET_NAME)",
    "SKIP_INSTALL"              => "YES",
    "MARKETING_VERSION"         => "1.0",
    "CURRENT_PROJECT_VERSION"   => "1",
    "TARGETED_DEVICE_FAMILY"    => "1,2",
    "LD_RUNPATH_SEARCH_PATHS"   => ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"]
  )
end

# 2. Group + file refs for the extension's own files.
grp = proj.main_group.find_subpath("ShareExtension", true)
grp.set_source_tree("SOURCE_ROOT")
svc_ref  = grp.new_reference("ShareExtension/ShareViewController.swift")
grp.new_reference("ShareExtension/Info.plist")              # nav only (set via build setting)
grp.new_reference("ShareExtension/ShareExtension.entitlements")

# 3. Reuse the already-in-project core files (membership in two targets).
shared_paths = ["PantryChef/Shared/SharedRecipeInbox.swift", "PantryChef/Shared/ShareItemExtractor.swift"]
shared_refs = shared_paths.map do |p|
  ref = proj.files.find { |f| f.real_path.to_s.end_with?(p) }
  raise "missing shared file ref: #{p}" unless ref
  ref
end
ext.add_file_references([svc_ref] + shared_refs)

# 4. App gets the App-Group entitlement.
app_grp = proj.main_group.find_subpath("PantryChef", true)
app_grp.new_reference("PantryChef/PantryChef.entitlements")
app.build_configurations.each do |c|
  c.build_settings["CODE_SIGN_ENTITLEMENTS"] = "PantryChef/PantryChef.entitlements"
end

# 5. App depends on + embeds the extension.
app.add_dependency(ext)
embed = app.new_copy_files_build_phase("Embed App Extensions")
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(ext.product_reference)
bf.settings = { "ATTRIBUTES" => ["RemoveHeadersOnCopy"] }

proj.save
puts "OK: ShareExtension target created and embedded."
puts "  ext sources: #{ext.source_build_phase.files.map { |f| f.file_ref.display_name }.join(', ')}"
puts "  app embed phase: #{embed.display_name} -> #{embed.files.map { |f| f.file_ref.display_name }.join(', ')}"
