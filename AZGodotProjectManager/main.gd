extends Control

const UI = preload("res://ui/ui.gd")
const Mark = preload("res://ui/mark.gd")
const Row = preload("res://ui/project_row.gd")
const EnvironmentDialog = preload("res://ui/environment_dialog.gd")
const Projects = preload("res://scripts/projects.gd")
const Runner = preload("res://scripts/process_runner.gd")

@export var settings_file := "user://manager.cfg"
var store := ConfigFile.new()
var projects: Dictionary = {}
var descriptions: Dictionary = {}
var selected := ""
var queue := PackedStringArray()
var building := ""
var logs: Dictionary = {}
var scan_thread: Thread
var environment := EnvironmentDialog.new()

var rows: VBoxContainer
var empty: CenterContainer
var empty_title: Label
var empty_hint: Label
var filter: LineEdit
var order: OptionButton
var open_button: Button
var summary: Label
var env_status: Label
var log_panel: PanelContainer
var log_text: TextEdit
var log_title: Label
var create_dialog: ConfirmationDialog
var new_name: LineEdit
var new_parent: LineEdit
var new_cpp: CheckBox

func _ready() -> void:
	get_window().min_size = Vector2i(800, 490)
	get_window().title = "AZGodotProjectManager · 项目管理器"
	theme = UI.theme()
	if FileAccess.file_exists(settings_file):
		store.load(settings_file)
	projects = store.get_value("projects", "items", {})
	for path in projects:
		if projects[path].get("build", "") == "building":
			projects[path] = {"build":"failed", "message":"上次构建中断，请重试。"}
	environment.engine_path = store.get_value("environment", "engine_path", "")
	environment.engine_version = store.get_value("environment", "engine_version", "")
	environment.sdk_path = store.get_value("environment", "sdk_path", "")
	add_child(environment)
	environment.engine_changed.connect(_engine_changed)
	environment.sdk_changed.connect(_sdk_changed)
	_build_ui()
	_update_environment()
	refresh()
	get_window().focus_entered.connect(_refresh_metadata)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 0)
	add_child(layout)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UI.box(Color("#191c21"), 0, Color.TRANSPARENT, 25, 15))
	layout.add_child(header)
	var bar := HBoxContainer.new()
	header.add_child(bar)
	var mark := Mark.new()
	mark.custom_minimum_size = Vector2(32, 32)
	bar.add_child(mark)
	bar.add_child(UI.label("AZGodotProjectManager", 22))
	bar.add_child(VSeparator.new())
	bar.add_child(UI.label("项目管理器", 16, UI.MUTED))
	UI.spacer(bar)
	bar.add_child(UI.button("打开原版 Godot", open_manager))
	bar.add_child(UI.button("环境设置", open_settings))
	var content := UI.padding(layout, 23, 18)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	content.add_child(body)
	var tools := HBoxContainer.new()
	body.add_child(tools)
	tools.add_child(UI.button("＋ 创建", _new_project, true))
	tools.add_child(UI.button("导入…", _import_project))
	tools.add_child(UI.button("扫描…", _scan_projects))
	filter = LineEdit.new()
	filter.placeholder_text = "筛选项目名称或路径"
	filter.clear_button_enabled = true
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(func(_text): refresh())
	tools.add_child(filter)
	order = OptionButton.new()
	order.add_item("最近修改")
	order.add_item("项目名称")
	order.item_selected.connect(func(_index): refresh())
	tools.add_child(order)
	var caption := HBoxContainer.new()
	body.add_child(caption)
	summary = UI.label("项目", 14, UI.MUTED)
	caption.add_child(summary)
	UI.spacer(caption)
	open_button = UI.button("打开项目", func(): open_project(selected))
	caption.add_child(open_button)
	var list_area := PanelContainer.new()
	list_area.add_theme_stylebox_override("panel", UI.box(Color("#1b1e22"), 7, UI.LINE, 7, 7))
	list_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_area)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_area.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	empty = CenterContainer.new()
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_area.add_child(empty)
	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_theme_constant_override("separation", 10)
	empty.add_child(center)
	var glyph := Mark.new()
	glyph.folder = true
	glyph.custom_minimum_size = Vector2(58, 58)
	glyph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(glyph)
	empty_title = UI.label("", 20)
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(empty_title)
	empty_hint = UI.label("", 14, UI.MUTED)
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(empty_hint)
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", UI.box(Color("#191c20"), 5, UI.LINE))
	log_panel.visible = false
	body.add_child(log_panel)
	var log_box := VBoxContainer.new()
	log_panel.add_child(log_box)
	var log_header := HBoxContainer.new()
	log_box.add_child(log_header)
	log_title = UI.label("构建输出", 14, UI.MUTED)
	log_header.add_child(log_title)
	UI.spacer(log_header)
	log_header.add_child(UI.button("收起", func(): log_panel.hide()))
	log_text = TextEdit.new()
	log_text.editable = false
	log_text.custom_minimum_size.y = 104
	log_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	log_text.add_theme_font_size_override("font_size", 13)
	log_box.add_child(log_text)
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UI.box(Color("#191c21"), 0, Color.TRANSPARENT, 23, 6))
	layout.add_child(footer)
	var foot := HBoxContainer.new()
	footer.add_child(foot)
	env_status = UI.label("", 13, UI.MUTED)
	foot.add_child(env_status)
	UI.spacer(foot)
	foot.add_child(UI.button("构建输出", func(): log_panel.visible = not log_panel.visible; _show_log()))

func _save() -> void:
	store.set_value("projects", "items", projects)
	var error := store.save(settings_file)
	if error != OK:
		UI.notice(self, "无法保存设置", error_string(error))

func _engine_changed(path: String, version: String) -> void:
	store.set_value("environment", "engine_path", path)
	store.set_value("environment", "engine_version", version)
	_save()
	_update_environment()

func _sdk_changed(path: String) -> void:
	store.set_value("environment", "sdk_path", path)
	_save()
	_update_environment()

func _update_environment() -> void:
	var engine := "Godot 未配置" if environment.engine_version.is_empty() else "Godot " + environment.engine_version.get_slice(".stable", 0)
	env_status.text = engine + "    ·    " + ("godot-cpp 4.7 API" if not environment.sdk_path.is_empty() and Projects.sdk_valid(environment.sdk_path) else "godot-cpp 未配置")

func open_settings() -> void:
	environment.refresh()
	environment.popup_centered_clamped(Vector2i(680, 370), 0.94)

func _key(path: String) -> String:
	var normalized := Projects.normalize(path)
	if OS.get_name() == "Windows":
		for existing in projects:
			if normalized.nocasecmp_to(existing) == 0:
				return existing
	return normalized

func state_of(info: Dictionary) -> String:
	if not str(info.error).is_empty():
		return "missing"
	if building == info.root:
		return "building"
	if queue.has(info.root):
		return "queued"
	if projects.get(info.root, {}).get("build", "") == "failed":
		return "failed"
	if info.managed:
		return "enabled"
	return "native" if info.native else "plain"

func _refresh_metadata() -> void:
	descriptions.clear()
	refresh()

func refresh() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var listed: Array[Dictionary] = []
	var query := filter.text.strip_edges().to_lower()
	for path in projects:
		if not descriptions.has(path):
			descriptions[path] = Projects.describe(path)
		var info: Dictionary = descriptions[path]
		if query.is_empty() or (str(info.name) + " " + str(path)).to_lower().contains(query):
			listed.append(info)
	listed.sort_custom(func(a, b):
		if order.selected == 0 and a.time != b.time: return a.time > b.time
		return a.name.naturalnocasecmp_to(b.name) < 0)
	if not listed.any(func(item): return item.root == selected):
		selected = "" if listed.is_empty() else str(listed[0].root)
	for info in listed:
		var row := Row.new()
		row.setup(info, state_of(info), selected == info.root)
		row.selected.connect(_select)
		row.open_requested.connect(open_project)
		row.enable_requested.connect(request_enable)
		rows.add_child(row)
	summary.text = "项目  ·  %d" % listed.size()
	empty.visible = listed.is_empty()
	empty_title.text = "还没有项目" if projects.is_empty() else "没有匹配的项目"
	empty_hint.text = "创建一个项目，或导入已有的 project.godot。" if projects.is_empty() else "试试其他名称或目录。"
	open_button.disabled = selected.is_empty() or not FileAccess.file_exists(Projects.settings(selected))
	_show_log()

func _select(path: String) -> void:
	selected = path
	for row in rows.get_children():
		row.active = row.root == path
		row._style()
	open_button.disabled = not FileAccess.file_exists(Projects.settings(path))
	_show_log()

func open_project(path: String) -> int:
	if path.is_empty(): return -1
	if not FileAccess.file_exists(Projects.settings(path)):
		UI.notice(self, "无法打开项目", "找不到 " + Projects.settings(path))
		return -1
	return _launch(["--editor", "--path", path])

func open_manager() -> int:
	return _launch(["--project-manager"])

func _launch(arguments: PackedStringArray) -> int:
	var engine: String = environment.engine_path
	if not FileAccess.file_exists(engine) or not Projects.engine_supported(environment.engine_version):
		open_settings()
		environment.engine_note.text = "请先选择兼容的 Godot 编辑器。"
		return -1
	var pid := OS.create_process(engine, arguments)
	if pid < 0:
		UI.notice(self, "启动失败", engine)
	return pid

func _new_project() -> void:
	create_dialog = ConfirmationDialog.new()
	create_dialog.title = "创建项目"
	create_dialog.dialog_hide_on_ok = false
	create_dialog.get_ok_button().text = "创建"
	create_dialog.get_cancel_button().text = "取消"
	var form := VBoxContainer.new()
	create_dialog.add_child(form)
	var line := UI.field(form, "项目名称")
	new_name = LineEdit.new()
	new_name.placeholder_text = "MyGame"
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(new_name)
	line = UI.field(form, "父目录（将创建同名项目文件夹）")
	new_parent = LineEdit.new()
	new_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_parent.text = store.get_value("projects", "last_parent", "")
	line.add_child(new_parent)
	line.add_child(UI.button("浏览…", func(): UI.picker(create_dialog, "选择父目录", FileDialog.FILE_MODE_OPEN_DIR, func(p): new_parent.text = p)))
	new_cpp = CheckBox.new()
	new_cpp.text = "使用 C++（AZGodotBuildTool）"
	form.add_child(new_cpp)
	create_dialog.confirmed.connect(_create_confirmed)
	_modal(create_dialog, Vector2i(540, 270))
	new_name.grab_focus()

func _modal(dialog: AcceptDialog, dialog_size: Vector2i) -> void:
	add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())
	dialog.popup_centered_clamped(dialog_size, 0.9)

func _create_confirmed() -> void:
	var cpp := new_cpp.button_pressed
	if cpp and not _environment_ready():
		UI.notice(create_dialog, "C++ 环境未就绪", "请先在环境设置中选择 godot-cpp，并确认构建工具可用。")
		return
	var parent := Projects.normalize(new_parent.text.strip_edges())
	var result := Projects.create(parent, new_name.text, cpp)
	if not str(result.error).is_empty():
		UI.notice(create_dialog, "无法创建项目", result.error)
		return
	store.set_value("projects", "last_parent", parent)
	create_dialog.hide()
	register_paths([result.root], false)
	if cpp: request_enable(result.root)

func _import_project() -> void:
	UI.picker(self, "导入 Godot 项目", FileDialog.FILE_MODE_OPEN_ANY, import_path)

func import_path(path: String) -> void:
	var root := path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
	if (not DirAccess.dir_exists_absolute(path) and path.get_file() != "project.godot") or not FileAccess.file_exists(Projects.settings(root)):
		UI.notice(self, "无法导入", "请选择 project.godot 或包含它的项目目录。")
		return
	register_paths([root], true)

func _scan_projects() -> void:
	if scan_thread != null: return
	UI.picker(self, "扫描目录", FileDialog.FILE_MODE_OPEN_DIR, scan_path)

func scan_path(path: String) -> void:
	if scan_thread != null: return
	summary.text = "正在扫描项目…"
	scan_thread = Thread.new()
	var error := scan_thread.start(Projects.scan.bind(path))
	if error != OK:
		scan_thread = null
		refresh()
		UI.notice(self, "无法扫描", error_string(error))
		return
	while scan_thread.is_alive():
		await get_tree().process_frame
	var paths: PackedStringArray = scan_thread.wait_to_finish()
	scan_thread = null
	if paths.is_empty():
		refresh()
		UI.notice(self, "扫描完成", "所选目录内没有找到 project.godot。")
	else:
		register_paths(paths, true)

func register_paths(paths: PackedStringArray, offer_cpp: bool) -> void:
	var candidates := PackedStringArray()
	for path in paths:
		var key := _key(path)
		var info := Projects.describe(key)
		if not str(info.error).is_empty():
			UI.notice(self, "无法读取项目", Projects.settings(key))
			continue
		if not projects.has(key): projects[key] = {}
		descriptions[key] = info
		if not info.managed and state_of(info) in ["plain", "native", "failed"]: candidates.append(key)
		selected = key
	_save()
	refresh()
	if offer_cpp and not candidates.is_empty():
		_offer_conversion(candidates)

func _offer_conversion(paths: PackedStringArray) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "启用 C++"
	dialog.get_cancel_button().text = "保留当前项目"
	var checks: Array[CheckBox] = []
	if paths.size() == 1:
		dialog.dialog_text = "为「%s」启用 C++ 项目结构并执行首次构建吗？\n%s" % [Projects.describe(paths[0]).name, paths[0]]
		dialog.dialog_autowrap = true
		dialog.get_ok_button().text = "启用 C++"
	else:
		dialog.get_ok_button().text = "启用选中的项目"
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = 145
		dialog.add_child(scroll)
		var list := VBoxContainer.new()
		scroll.add_child(list)
		list.add_child(UI.label("选择要接入 C++ 构建的项目", 14, UI.MUTED))
		for path in paths:
			var check := CheckBox.new()
			check.text = "%s  ·  %s" % [Projects.describe(path).name, path]
			check.tooltip_text = path
			list.add_child(check)
			checks.append(check)
	dialog.confirmed.connect(func():
		if not _environment_ready():
			open_settings()
			environment.sdk_note.text = "配置完成后，点击对应项目行的「启用 C++」。"
			return
		for i in paths.size():
			if paths.size() == 1 or checks[i].button_pressed:
				request_enable(paths[i]))
	_modal(dialog, Vector2i(610, 255 if paths.size() > 1 else 175))

func _environment_ready() -> bool:
	return not environment.sdk_path.is_empty() and Projects.sdk_valid(environment.sdk_path) and FileAccess.file_exists(Projects.tool_path())

func request_enable(path: String) -> void:
	path = _key(path)
	if not projects.has(path) or queue.has(path) or path == building: return
	if not _environment_ready():
		refresh()
		open_settings()
		environment.sdk_note.text = "启用 C++ 需要兼容的 godot-cpp。" if not Projects.sdk_valid(environment.sdk_path) else "找不到构建工具：" + Projects.tool_path()
		return
	selected = path
	queue.append(path)
	refresh()
	if building.is_empty(): _next_build()

func _next_build() -> void:
	if queue.is_empty() or not building.is_empty(): return
	var path := queue[0]
	queue.remove_at(0)
	building = path
	var sdk: String = environment.sdk_path
	var tool := Projects.tool_path()
	projects[path] = {"build":"building"}
	logs[path] = ""
	_save()
	log_panel.show()
	refresh()
	var problem := Projects.enable_cpp(path, sdk, tool)
	if problem.is_empty():
		var ide := "vs" if OS.get_name() == "Windows" else "cmake"
		for args in [PackedStringArray(["generate", "--ide", ide]), PackedStringArray(["build"])]:
			_append_log(path, "> AZGodotBuildTool " + " ".join(args) + "\n")
			var result := await Runner.build(get_tree(), path, tool, args, func(chunk): _append_log(path, chunk))
			if result.code != 0:
				problem = "构建命令退出码 %s\n%s" % [result.code, str(result.text).right(3000)]
				break
	if not problem.is_empty(): _append_log(path, problem + "\n")
	projects[path] = {"build":"ready"} if problem.is_empty() else {"build":"failed", "message":problem}
	descriptions.erase(path)
	building = ""
	_save()
	refresh()
	_next_build.call_deferred()

func _append_log(path: String, chunk: String) -> void:
	logs[path] = (str(logs.get(path, "")) + chunk).right(40000)
	if path == selected and log_panel.visible: _show_log()

func _show_log() -> void:
	if not log_panel.visible: return
	log_title.text = "构建输出" if selected.is_empty() else "构建输出  ·  " + selected.get_file()
	log_text.text = logs.get(selected, projects.get(selected, {}).get("message", "暂无构建输出"))
	log_text.scroll_vertical = log_text.get_line_count()

func _exit_tree() -> void:
	if scan_thread != null and scan_thread.is_started():
		scan_thread.wait_to_finish()
