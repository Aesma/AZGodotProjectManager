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
		finished.emit("", "请选择支持的版本和现有目录。")
		return
	destination = parent.path_join("godot-cpp-" + version)
	if DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		if Projects.sdk_valid(destination):
			finished.emit(destination, "")
		else:
			finished.emit("", "目标已存在，请选择其他保存目录。")
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
		_complete("无法开始下载：" + error_string(err))

func _process(_delta: float) -> void:
	if busy and is_instance_valid(request):
		progress.emit("正在下载 godot-cpp · %.1f MiB" % (request.get_downloaded_bytes() / 1048576.0))

func _received(result: int, status: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	request.queue_free()
	request = null
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		_complete("下载失败（HTTP %d，结果 %d）。" % [status, result])
		return
	progress.emit("正在解压 godot-cpp…")
	var error := await extract(get_tree(), archive, staging, destination)
	_complete(error)

static func extract(tree: SceneTree, zip_path: String, stage: String, dest: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "无法读取下载的 ZIP 文件。"
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
			return "压缩包内存在无效路径。"
		var file := stage.path_join(relative)
		if DirAccess.make_dir_recursive_absolute(file.get_base_dir()) != OK:
			zip.close()
			return "无法创建 SDK 目录。"
		var writer := FileAccess.open(file, FileAccess.WRITE)
		if writer == null or not writer.store_buffer(zip.read_file(entry)):
			zip.close()
			return "无法写入 " + file
		writer.close()
		count += 1
		if count % 48 == 0:
			await tree.process_frame
	zip.close()
	if not Projects.sdk_valid(stage):
		return "包中缺少 CMakeLists.txt 或 Godot 4.7 API。"
	if DirAccess.dir_exists_absolute(dest) or DirAccess.rename_absolute(stage, dest) != OK:
		return "无法安装到 " + dest
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
