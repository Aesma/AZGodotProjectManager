extends AcceptDialog

const UI = preload("res://ui/ui.gd")
const Projects = preload("res://scripts/projects.gd")
const Runner = preload("res://scripts/process_runner.gd")
const Installer = preload("res://scripts/sdk_installer.gd")
signal engine_changed(path: String, version: String)
signal sdk_changed(path: String)
var engine_path := ""
var engine_version := ""
var sdk_path := ""
var engine_line: LineEdit
var sdk_line: LineEdit
var engine_note: Label
var sdk_note: Label
var engine_button: Button
var installer := Installer.new()
var downloading: ConfirmationDialog
var save_path: LineEdit
var release: OptionButton
var parent_dir := ""
var sdk_prompt: ConfirmationDialog

func _ready() -> void:
	title = "环境设置"
	min_size = Vector2i(610, 345)
	get_ok_button().text = "完成"
	add_child(installer)
	installer.finished.connect(_installed)
	installer.progress.connect(func(message): sdk_note.text = message)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 9)
	add_child(form)
	var row := UI.field(form, "Godot 编辑器")
	engine_line = _path(row, "选择 Godot 可执行文件")
	engine_button = UI.button("浏览…", _browse_engine)
	row.add_child(engine_button)
	engine_note = UI.label("", 13, UI.MUTED)
	form.add_child(engine_note)
	form.add_child(HSeparator.new())
	row = UI.field(form, "godot-cpp 源码目录")
	sdk_line = _path(row, "选择包含 CMakeLists.txt 的目录")
	row.add_child(UI.button("浏览…", _browse_sdk))
	sdk_note = UI.label("", 13, UI.MUTED)
	form.add_child(sdk_note)
	refresh()

func _path(row: HBoxContainer, placeholder: String) -> LineEdit:
	var line := LineEdit.new()
	line.editable = false
	line.placeholder_text = placeholder
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(line)
	return line

func refresh() -> void:
	if not is_instance_valid(engine_line):
		return
	engine_line.text = engine_path
	engine_note.text = engine_version if not engine_version.is_empty() else "支持 Godot 4.7.x stable，已验证 4.7.2。"
	sdk_line.text = sdk_path
	sdk_note.text = "已找到 Godot 4.7 API" if not sdk_path.is_empty() and Projects.sdk_valid(sdk_path) else "支持 godot-cpp 10.0.0-stable（Godot 4.7 API）。"

func _browse_engine() -> void:
	var mode := FileDialog.FILE_MODE_OPEN_ANY if OS.get_name() == "macOS" else FileDialog.FILE_MODE_OPEN_FILE
	UI.picker(self, "选择 Godot 编辑器", mode, choose_engine, PackedStringArray(["*.exe ; Godot 编辑器"]) if OS.get_name() == "Windows" else PackedStringArray())

func choose_engine(path: String) -> void:
	engine_button.disabled = true
	engine_note.text = "正在读取引擎版本…"
	var binary := Projects.engine_binary(path)
	var result := {"code":-1, "text":"文件不存在"}
	if FileAccess.file_exists(binary):
		result = await Runner.run(get_tree(), binary, ["--version"], Callable(), 8000)
	var version := str(result.text).strip_edges()
	var problem := ""
	if result.code != 0 or not Projects.engine_supported(version):
		problem = "所选版本：%s\n支持范围：Godot 4.7.x stable。" % (version.left(150) if not version.is_empty() else "未知")
	else:
		var help := await Runner.run(get_tree(), binary, ["--help"], Callable(), 8000)
		if help.code != 0 or not str(help.text).contains("--project-manager"):
			problem = "所选程序不提供项目管理器，请选择 Godot 编辑器。"
	if problem.is_empty():
		engine_path = binary
		engine_version = version
		engine_changed.emit(binary, version)
	else:
		UI.notice(self if visible else get_parent(), "无法使用这个引擎", problem)
	engine_button.disabled = false
	refresh()

func _browse_sdk() -> void:
	if not installer.busy:
		UI.picker(self, "选择 godot-cpp 源码目录", FileDialog.FILE_MODE_OPEN_DIR, choose_sdk)

func choose_sdk(path: String) -> void:
	path = Projects.normalize(path)
	if Projects.sdk_valid(path):
		_installed(path, "")
		return
	sdk_prompt = ConfirmationDialog.new()
	sdk_prompt.title = "未找到兼容的 godot-cpp"
	sdk_prompt.dialog_text = "所选目录缺少 CMakeLists.txt 或 4.7 API。\n要选择版本并下载 godot-cpp 吗？"
	sdk_prompt.get_ok_button().text = "选择下载版本…"
	sdk_prompt.get_cancel_button().text = "取消"
	sdk_prompt.add_button("重新选择", true, "browse")
	sdk_prompt.custom_action.connect(func(_action): sdk_prompt.hide(); _browse_sdk())
	sdk_prompt.confirmed.connect(func(): _download_options(path))
	_attach(sdk_prompt)
	sdk_prompt.popup_centered(Vector2i(520, 175))

func _attach(dialog: AcceptDialog) -> void:
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())

func _download_options(parent: String) -> void:
	parent_dir = parent
	downloading = ConfirmationDialog.new()
	downloading.title = "下载 godot-cpp"
	downloading.get_ok_button().text = "确认下载"
	downloading.get_cancel_button().text = "取消"
	var form := VBoxContainer.new()
	downloading.add_child(form)
	var row := UI.field(form, "支持的版本")
	release = OptionButton.new()
	release.add_item(Projects.SDK_TAG)
	row.add_child(release)
	row = UI.field(form, "官方来源")
	_path(row, "").text = Projects.SDK_URL
	row = UI.field(form, "安装位置")
	save_path = _path(row, "")
	save_path.text = parent_dir.path_join("godot-cpp-" + Projects.SDK_TAG)
	row.add_child(UI.button("选择父目录…", func(): UI.picker(downloading, "选择保存目录", FileDialog.FILE_MODE_OPEN_DIR, _set_download_dir)))
	downloading.confirmed.connect(func(): installer.start(parent_dir, release.get_item_text(release.selected)))
	_attach(downloading)
	downloading.popup_centered(Vector2i(660, 300))

func _set_download_dir(path: String) -> void:
	parent_dir = path
	save_path.text = path.path_join("godot-cpp-" + release.get_item_text(release.selected))

func _installed(path: String, error: String) -> void:
	if error.is_empty():
		sdk_path = Projects.normalize(path)
		sdk_changed.emit(sdk_path)
	else:
		UI.notice(self if visible else get_parent(), "godot-cpp 安装失败", error)
	refresh()
