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
	title = "Environment Settings"
	min_size = Vector2i(610, 345)
	get_ok_button().text = "Done"
	add_child(installer)
	installer.finished.connect(_installed)
	installer.progress.connect(func(message): sdk_note.text = message)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	add_child(form)
	var row := _version_field(form, "Godot editor", "Supported Godot editors\n4.7.x stable (tested with 4.7.2)")
	engine_line = _path(row, "Select a Godot executable")
	engine_button = UI.button("Browse…", _browse_engine)
	row.add_child(engine_button)
	engine_note = UI.label("", 14, UI.MUTED)
	form.add_child(engine_note)
	form.add_child(HSeparator.new())
	row = _version_field(form, "godot-cpp source directory", "Supported godot-cpp versions\n10.0.0-stable (Godot 4.7 API)")
	sdk_line = _path(row, "Select the folder containing CMakeLists.txt")
	row.add_child(UI.button("Browse…", _browse_sdk))
	sdk_note = UI.label("", 14, UI.MUTED)
	form.add_child(sdk_note)
	refresh()

func _version_field(form: VBoxContainer, caption: String, message: String) -> HBoxContainer:
	var header := HBoxContainer.new()
	form.add_child(header)
	var heading := UI.label(caption, 16)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var hint := UI.label("?", 16, Color.WHITE)
	hint.custom_minimum_size = Vector2(24, 24)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_stylebox_override("normal", UI.box(Color("#494e56"), 12, Color.TRANSPARENT, 0, 0))
	hint.mouse_filter = Control.MOUSE_FILTER_STOP
	hint.mouse_default_cursor_shape = Control.CURSOR_HELP
	hint.tooltip_text = message
	header.add_child(hint)
	var row := HBoxContainer.new()
	form.add_child(row)
	return row

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
	engine_note.text = engine_version if not engine_version.is_empty() else "Godot not configured"
	sdk_line.text = sdk_path
	if sdk_path.is_empty():
		sdk_note.text = "godot-cpp not configured"
	else:
		sdk_note.text = "SDK detected" if Projects.sdk_valid(sdk_path) else "Compatible godot-cpp not found"

func _browse_engine() -> void:
	var mode := FileDialog.FILE_MODE_OPEN_ANY if OS.get_name() == "macOS" else FileDialog.FILE_MODE_OPEN_FILE
	UI.picker(self, "Select Godot Editor", mode, choose_engine, PackedStringArray(["*.exe ; Godot editor"]) if OS.get_name() == "Windows" else PackedStringArray())

func choose_engine(path: String) -> void:
	engine_button.disabled = true
	engine_note.text = "Checking engine version…"
	var binary := Projects.engine_binary(path)
	var result := {"code":-1, "text":"File not found"}
	if FileAccess.file_exists(binary):
		result = await Runner.run(get_tree(), binary, ["--version"], Callable(), 8000)
	var version := str(result.text).strip_edges()
	var problem := ""
	if result.code != 0 or not Projects.engine_supported(version):
		var detail := tr("Unknown") if version.is_empty() else version.left(150)
		if version == "File not found": detail = tr("File not found")
		problem = tr("Selected version: %s\nSupported versions: Godot 4.7.x stable.") % detail
	else:
		var help := await Runner.run(get_tree(), binary, ["--help"], Callable(), 8000)
		if help.code != 0 or not str(help.text).contains("--project-manager"):
			problem = "This program does not include the project manager. Select the Godot editor."
	if problem.is_empty():
		engine_path = binary
		engine_version = version
		engine_changed.emit(binary, version)
	else:
		UI.notice(self if visible else get_parent(), "Unsupported engine", problem)
	engine_button.disabled = false
	refresh()

func _browse_sdk() -> void:
	if not installer.busy:
		UI.picker(self, "Select godot-cpp Source Directory", FileDialog.FILE_MODE_OPEN_DIR, choose_sdk)

func choose_sdk(path: String) -> void:
	path = Projects.normalize(path)
	if Projects.sdk_valid(path):
		_installed(path, "")
		return
	sdk_prompt = ConfirmationDialog.new()
	sdk_prompt.title = "Compatible godot-cpp not found"
	sdk_prompt.dialog_text = "This folder is missing CMakeLists.txt or the 4.7 API.\nChoose a version of godot-cpp to download?"
	sdk_prompt.get_ok_button().text = "Choose version…"
	sdk_prompt.get_cancel_button().text = "Cancel"
	sdk_prompt.add_button("Choose another folder", true, "browse")
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
	downloading.title = "Download godot-cpp"
	downloading.get_ok_button().text = "Confirm download"
	downloading.get_cancel_button().text = "Cancel"
	var form := VBoxContainer.new()
	downloading.add_child(form)
	var row := UI.field(form, "Supported version")
	release = OptionButton.new()
	release.add_item(Projects.SDK_TAG)
	row.add_child(release)
	row = UI.field(form, "Official source")
	_path(row, "").text = Projects.SDK_URL
	row = UI.field(form, "Install location")
	save_path = _path(row, "")
	save_path.text = parent_dir.path_join("godot-cpp-" + Projects.SDK_TAG)
	row.add_child(UI.button("Choose parent folder…", func(): UI.picker(downloading, "Select Download Folder", FileDialog.FILE_MODE_OPEN_DIR, _set_download_dir)))
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
		UI.notice(self if visible else get_parent(), "Could not install godot-cpp", error)
	refresh()
