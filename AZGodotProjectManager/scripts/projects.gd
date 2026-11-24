extends RefCounted

const SECTION := "AZGodotBuildTool"
const SDK_TAG := "10.0.0-stable"
const SDK_URL := "https://codeload.github.com/godotengine/godot-cpp/zip/refs/tags/10.0.0-stable"
const API_RANGE: JSON = preload("res://scripts/godot_api_range.json")
static var supported_apis := _supported_apis()
static var feature_version := RegEx.create_from_string(r"^([0-9]+\.[0-9]+)(?:\.[0-9]+)?$")
static var stable_version := RegEx.create_from_string(r"^([0-9]+\.[0-9]+)(?:\.[0-9]+)?\.stable(?:\.|$)")

static func _supported_apis() -> PackedStringArray:
	var versions := PackedStringArray()
	for minor in range(int(API_RANGE.data.MinMinor), int(API_RANGE.data.MaxMinor) + 1):
		versions.append("%d.%d" % [API_RANGE.data.Major, minor])
	return versions

static func api_range_text() -> String:
	return "%s–%s" % [supported_apis[0], supported_apis[-1]]

static func project_api(cfg: ConfigFile) -> String:
	for feature in cfg.get_value("application", "config/features", PackedStringArray()):
		var matched := feature_version.search(str(feature))
		if matched: return matched.get_string(1)
	return ""

static func normalize(path: String) -> String:
	return path.replace("\\", "/").simplify_path()

static func settings(root: String) -> String:
	return root.path_join("project.godot")

static func sdk_valid(path: String, api := "") -> bool:
	if path.is_empty() or not FileAccess.file_exists(path.path_join("CMakeLists.txt")):
		return false
	for version in supported_apis:
		if (api.is_empty() or api == version) and FileAccess.file_exists(path.path_join("gdextension/extension_api-%s.json" % version.replace(".", "-"))):
			return true
	return false

static func cpp_api_issue(api: String, sdk: String) -> Dictionary:
	if api.is_empty():
		return {"issue":"No Godot version in project.godot [application] config/features."}
	if api not in supported_apis:
		return {"issue":"Project uses Godot %s. Supported versions: %s.", "args":[api, api_range_text()]}
	if not sdk_valid(sdk, api):
		return {"issue":"Select godot-cpp with the Godot %s API in Environment Settings.", "args":[api]}
	return {}

static func tool_path() -> String:
	var bundled := OS.get_executable_path().get_base_dir().path_join("BuildTool/AZGodotBuildTool.dll")
	if FileAccess.file_exists(bundled):
		return bundled
	return normalize(ProjectSettings.globalize_path("res://").path_join("../AZGodotBuildTool/bin/Debug/net10.0/AZGodotBuildTool.dll"))

static func engine_binary(path: String) -> String:
	path = normalize(path)
	if OS.get_name() == "macOS" and path.ends_with(".app"):
		return path.path_join("Contents/MacOS/Godot")
	return path

static func engine_api(version: String) -> String:
	var matched := stable_version.search(version.strip_edges())
	return matched.get_string(1) if matched else ""

static func engine_supported(version: String) -> bool:
	return engine_api(version) in supported_apis

static func new_project_api(editor_version: String) -> String:
	if not editor_version.is_empty():
		return engine_api(editor_version)
	var host := Engine.get_version_info()
	return "%d.%d" % [host.major, host.minor]

static func modules_exist(root: String) -> bool:
	var dirs := PackedStringArray([root.path_join("Source")])
	var addons := root.path_join("addons")
	if DirAccess.dir_exists_absolute(addons):
		for addon in DirAccess.get_directories_at(addons):
			dirs.append(addons.path_join(addon).path_join("Source"))
	for dir in dirs:
		if DirAccess.dir_exists_absolute(dir):
			for module in DirAccess.get_directories_at(dir):
				if _has_cpp(dir.path_join(module), true):
					return true
	return false

static func _has_cpp(root: String, headers: bool) -> bool:
	var access := DirAccess.open(root)
	if access == null: return false
	for file in access.get_files():
		var ext := file.get_extension().to_lower()
		if ext in ["cpp", "cc", "cxx"] or (headers and ext in ["hpp", "hxx", "hh", "h"]):
			return true
	for part in access.get_directories():
		var child := root.path_join(part)
		if part.begins_with(".") or part.to_lower() in ["thirdparty", "third_party", "godot-cpp", "build", "bin", "obj"] or access.is_link(part):
			continue
		if not FileAccess.file_exists(settings(child)) and _has_cpp(child, headers):
			return true
	return false

static func describe(root: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var path := settings(root)
	var err := cfg.load(path)
	if err != OK:
		return {"root":root, "name":root.get_file(), "error":"Could not read project.godot", "version":"", "managed":false, "native":false, "icon":"", "time":0}
	var version := project_api(cfg)
	var icon := str(cfg.get_value("application", "config/icon", ""))
	var native := modules_exist(root)
	return {"root":root, "name":str(cfg.get_value("application", "config/name", root.get_file())),
		"error":"", "version":version, "managed":cfg.has_section(SECTION) and native,
		"native":native or _has_cpp(root, false), "icon":root.path_join(icon.trim_prefix("res://")) if icon.begins_with("res://") else "",
		"time":FileAccess.get_modified_time(path)}

static func scan(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var pending := PackedStringArray([normalize(root)])
	while not pending.is_empty():
		var dir: String = pending[pending.size() - 1]
		pending.resize(pending.size() - 1)
		var access := DirAccess.open(dir)
		if access == null or FileAccess.file_exists(dir.path_join(".gdignore")):
			continue
		if FileAccess.file_exists(settings(dir)):
			found.append(dir)
		for child in access.get_directories():
			if not child.begins_with(".") and not access.is_link(child):
				pending.append(dir.path_join(child))
	return found

static func write_text(path: String, text: String) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	return OK if f.store_string(text) else ERR_FILE_CANT_WRITE

static func create(parent: String, title: String, cpp: bool, editor_version := "") -> Dictionary:
	title = title.strip_edges()
	if title.is_empty() or not title.is_valid_filename() or title in [".", ".."]:
		return {"error":"Enter a valid project name."}
	if not parent.is_absolute_path() or not DirAccess.dir_exists_absolute(parent):
		return {"error":"Select a parent folder for the project."}
	var root := normalize(parent.path_join(title))
	if DirAccess.dir_exists_absolute(root) or FileAccess.file_exists(root):
		return {"error":"The destination already exists. Choose another project name."}
	var api := new_project_api(editor_version)
	if api not in supported_apis:
		return {"error":TranslationServer.translate("Select a compatible Godot editor first.")}
	var config := "config_version=5\n\n[application]\nconfig/name=%s\nrun/main_scene=\"res://Main.tscn\"\nconfig/features=PackedStringArray(\"%s\", \"GL Compatibility\")\n\n[rendering]\nrenderer/rendering_method=\"gl_compatibility\"\n" % [JSON.stringify(title), api]
	var scene := '[gd_scene format=3]\n\n[node name="Main" type="Node"]\n'
	if cpp:
		scene += '\n[node name="ProjectNode" type="ProjectNode" parent="."]\n'
	var stage := parent.path_join(".azgodotprojectmanager-new-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var err := write_text(stage.path_join("Main.tscn"), scene)
	if err == OK:
		err = write_text(settings(stage), config)
	if err == OK:
		err = DirAccess.rename_absolute(stage, root)
	if err != OK and DirAccess.dir_exists_absolute(stage):
		for file in DirAccess.get_files_at(stage):
			DirAccess.remove_absolute(stage.path_join(file))
		DirAccess.remove_absolute(stage)
	return {"root":root, "error":"" if err == OK else TranslationServer.translate("Could not create project: %s") % error_string(err)}

static func enable_cpp(root: String, sdk: String, tool: String) -> Dictionary:
	var cfg := ConfigFile.new()
	var path := settings(root)
	if cfg.load(path) != OK:
		return {"issue":"Could not read %s", "args":[path]}
	var problem := cpp_api_issue(project_api(cfg), sdk)
	if not problem.is_empty(): return problem
	if not FileAccess.file_exists(tool):
		return {"issue":"AZGodotBuildTool.dll not found: %s", "args":[tool]}
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")
	var begin := -1
	var end := lines.size()
	for i in lines.size():
		var line := lines[i].get_slice(";", 0).strip_edges()
		if line == "[" + SECTION + "]":
			begin = i
		elif begin >= 0 and line.begins_with("["):
			end = i
			break
	var newline := "\r" if text.contains("\r\n") else ""
	var keys := {"tool_path":tool, "godot_cpp_path":sdk}
	if begin < 0:
		lines.append("[" + SECTION + "]" + newline)
		end = lines.size()
	else:
		for i in range(begin + 1, end):
			var key := lines[i].get_slice("=", 0).strip_edges()
			if keys.has(key):
				lines[i] = key + "=" + JSON.stringify(keys[key]) + newline
				keys.erase(key)
	for key in keys:
		lines.insert(end, str(key) + "=" + JSON.stringify(keys[key]) + newline)
		end += 1
	var updated := "\n".join(lines)
	if not updated.ends_with("\n"):
		updated += newline + "\n"
	if not modules_exist(root):
		var module := root.path_join("Source/Gameplay")
		# Stage the pair together. A retry cannot mistake a half-written module for an existing one.
		var staged := root.path_join(".build/launcher-template-" + str(Time.get_ticks_usec()))
		for spec in [["Public/ProjectNode.hpp", "ProjectNode.hpp.txt"], ["Private/ProjectNode.cpp", "ProjectNode.cpp.txt"]]:
			var dest := staged.path_join(spec[0])
			var content := FileAccess.get_file_as_string("res://templates/" + str(spec[1]))
			if content.is_empty() or write_text(dest, content) != OK:
				return {"issue":"Could not create C++ source file: %s", "args":[dest]}
		if DirAccess.dir_exists_absolute(module):
			# Leave an existing, non-native Gameplay directory intact.
			module = root.path_join("Source/ProjectNative")
		if DirAccess.make_dir_recursive_absolute(module.get_base_dir()) != OK or DirAccess.rename_absolute(staged, module) != OK:
			return {"issue":"Could not create C++ module: %s", "args":[module]}
	if updated != text:
		var temp := path + ".azgodotprojectmanager-" + str(Time.get_ticks_usec()) + ".tmp"
		var err := write_text(temp, updated)
		if err == OK:
			err = DirAccess.rename_absolute(temp, path)
		if err != OK:
			DirAccess.remove_absolute(temp)
			return {"issue":"Could not update project.godot: %s", "args":[error_string(err)]}
	return {}
