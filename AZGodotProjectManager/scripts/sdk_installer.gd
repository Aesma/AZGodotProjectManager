extends Node

const Projects = preload("res://scripts/projects.gd")
signal finished(path: String, error: String)
signal progress(message: String)
var request: HTTPRequest
var archive := ""
var staging := ""
var destination := ""
var busy := false

func start(parent: String, version: String) -> void:
	if busy:
		return
	if version != Projects.SDK_TAG or not DirAccess.dir_exists_absolute(parent):
		finished.emit("", "Select a supported version and an existing folder.")
		return
	destination = parent.path_join("godot-cpp-" + version)
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		if Projects.sdk_valid(destination):
			finished.emit(destination, "")
		else:
			finished.emit("", "The destination already exists. Select a different folder.")
		return
	var unique := ".azgodotprojectmanager-" + str(OS.get_process_id()) + "-" + str(Time.get_ticks_usec())
	archive = parent.path_join(unique + ".zip")
	staging = parent.path_join(unique)
	busy = true
	request = HTTPRequest.new()
	add_child(request)
	request.download_file = archive
	request.timeout = 120
	request.request_completed.connect(_received, CONNECT_ONE_SHOT)
	var err := request.request(Projects.SDK_URL)
	if err != OK:
		_complete(tr("Could not start download: %s") % error_string(err))

func _process(_delta: float) -> void:
	if busy and is_instance_valid(request):
		progress.emit(tr("Downloading godot-cpp · %.1f MiB") % (request.get_downloaded_bytes() / 1048576.0))

func _received(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	request.queue_free()
	request = null
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		_complete(tr("Download failed (HTTP %d, result %d).") % [status, result])
		return
	progress.emit("Extracting godot-cpp…")
	var error := await extract(get_tree(), archive, staging, destination)
	_complete(error)

static func extract(tree: SceneTree, zip_path: String, stage: String, dest: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "Could not read the downloaded ZIP file."
	var files := zip.get_files()
	var count := 0
	for entry in files:
		if entry.ends_with("/"):
			continue
		var slash := entry.find("/")
		if slash < 0:
			continue
		var relative := entry.substr(slash + 1)
		if relative.is_absolute_path() or relative.contains("\\") or relative.contains(":") or ".." in relative.split("/"):
			zip.close()
			return "The archive contains an invalid path."
		var file := stage.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(file.get_base_dir()) != OK:
			zip.close()
			return "Could not create the SDK directory."
		var writer := FileAccess.open(file, FileAccess.WRITE)
		if writer == null or not writer.store_buffer(zip.read_file(entry)):
			zip.close()
			return TranslationServer.translate("Could not write to %s") % file
		writer.close()
		count += 1
		if count % 48 == 0:
			await tree.process_frame
	zip.close()
	if not Projects.sdk_valid(stage):
		return TranslationServer.translate("The archive is missing CMakeLists.txt or a supported Godot API (%s).") % Projects.api_range_text()
	if DirAccess.dir_exists_absolute(dest) or DirAccess.rename_absolute(stage, dest) != OK:
		return TranslationServer.translate("Could not install to %s") % dest
	return ""

static func _remove_stage(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	access.include_hidden = true
	for file in access.get_files():
		access.remove(file)
	for child in access.get_directories():
		if access.is_link(child):
			access.remove(child)
		else:
			_remove_stage(dir.path_join(child))
	DirAccess.remove_absolute(dir)

func _complete(error: String) -> void:
	if is_instance_valid(request):
		request.queue_free()
	request = null
	if FileAccess.file_exists(archive):
		DirAccess.remove_absolute(archive)
	_remove_stage(staging)
	busy = false
	finished.emit(destination if error.is_empty() else "", error)
