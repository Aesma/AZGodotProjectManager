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
var empty_actions: HBoxContainer
var filter: LineEdit
var order: OptionButton
var language_menu: MenuButton
const LANGUAGES := ["zh_CN", "en"]
var open_button: Button
var output_button: Button
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
	_size_window(true)
	get_window().title = "AZGodotProjectManager · Project Manager"
	theme = UI.theme()
	if FileAccess.file_exists(settings_file):
		store.load(settings_file)
	var language = store.get_value("ui", "language", "")
	if language not in LANGUAGES:
		language = "zh_CN" if OS.get_locale_language() == "zh" else "en"
	TranslationServer.set_locale(language)
	projects = store.get_value("projects", "items", {})
	for path in projects:
		if projects[path].get("build", "") == "building":
			projects[path] = {"build":"failed", "issue":"The last build was interrupted. Retry to continue."}
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

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_DPI_CHANGE, NOTIFICATION_WM_POSITION_CHANGED] and is_node_ready() and is_inside_tree():
		_size_window(false)

func _size_window(initial: bool) -> void:
	var window := get_window()
	var screen := window.current_screen
	var usable := DisplayServer.screen_get_usable_rect(screen).size
	if usable.x <= 0 or usable.y <= 0: return
	var available := usable - (window.get_size_with_decorations() - window.size)
	var minimum := Vector2(720, 450)
	var scale_factor := minf(UI.display_scale(screen), minf(available.x / minimum.x, available.y / minimum.y))
	var previous := window.content_scale_factor
	if not initial and is_equal_approx(scale_factor, previous): return
	var logical := Vector2(window.size) / previous
	window.content_scale_factor = scale_factor
	window.min_size = Vector2i((minimum * scale_factor).floor())
	if window.mode == Window.MODE_WINDOWED and not OS.has_feature("embedded_in_editor"):
		if initial and "--resolution" not in OS.get_cmdline_args():
			logical = Vector2(1152, 800)
		elif initial:
			return
		window.size = Vector2i((logical * scale_factor).round()).min(available)
		if initial: window.move_to_center()

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
	header.custom_minimum_size.y = 44
	header.add_theme_stylebox_override("panel", UI.box(UI.BG, 0, Color.TRANSPARENT, 12, 4))
	layout.add_child(header)
	var bar := HBoxContainer.new()
	header.add_child(bar)
	var identity := HBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(identity)
	var mark := Mark.new()
	mark.custom_minimum_size = Vector2(24, 24)
	identity.add_child(mark)
	var brand := UI.label("AZGodotProjectManager", 19)
	brand.theme_type_variation = &"ManagerHeading"
	brand.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(brand)
	var project_icon := TextureRect.new()
	project_icon.texture = UI.icon("projects")
	project_icon.modulate = UI.BLUE
	project_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	bar.add_child(project_icon)
	summary = UI.label("Projects", 16, UI.BLUE)
	summary.theme_type_variation = &"ManagerHeading"
	bar.add_child(summary)
	var godot_button := UI.button("Open Godot", open_manager, "launch")
	godot_button.flat = true
	bar.add_child(godot_button)
	var preferences := HBoxContainer.new()
	preferences.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preferences.alignment = BoxContainer.ALIGNMENT_END
	bar.add_child(preferences)
	language_menu = MenuButton.new()
	language_menu.name = "LanguageMenu"
	language_menu.flat = true
	language_menu.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	language_menu.tooltip_text = "Interface language"
	preferences.add_child(language_menu)
	var options := language_menu.get_popup()
	options.add_radio_check_item("简体中文", 0)
	options.add_radio_check_item("English", 1)
	_update_language_button(LANGUAGES.find(TranslationServer.get_locale()))
	options.id_pressed.connect(_change_language)
	var settings := UI.button("Settings", open_settings, "settings")
	settings.flat = true
	preferences.add_child(settings)
	var content := UI.padding(layout, 4, 0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.box(UI.SURFACE, 5, Color.TRANSPARENT, 6, 6))
	content.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	panel.add_child(body)
	var tools := HBoxContainer.new()
	body.add_child(tools)
	tools.add_child(UI.button("Create", _new_project, "create"))
	tools.add_child(UI.button("Import…", _import_project, "folder"))
	tools.add_child(UI.button("Scan…", _scan_projects, "search"))
	filter = LineEdit.new()
	filter.placeholder_text = "Filter projects"
	filter.right_icon = UI.icon("search")
	filter.clear_button_enabled = true
	filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter.text_changed.connect(func(_text): refresh())
	tools.add_child(filter)
	tools.add_child(UI.label("Sort by", 15, UI.MUTED))
	order = OptionButton.new()
	order.custom_minimum_size = Vector2(196, 34)
	order.add_item("Last modified")
	order.add_item("Project name")
	order.item_selected.connect(func(_index): refresh())
	tools.add_child(order)
	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(workspace)
	var list_area := PanelContainer.new()
	list_area.add_theme_stylebox_override("panel", UI.box(UI.LIST, 4, Color.TRANSPARENT, 5, 5))
	list_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(list_area)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_area.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 2)
	scroll.add_child(rows)
	empty = CenterContainer.new()
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_area.add_child(empty)
	var center := VBoxContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_theme_constant_override("separation", 5)
	empty.add_child(center)
	empty_title = UI.label("", 16)
	empty_title.theme_type_variation = &"ManagerHeading"
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(empty_title)
	empty_hint = UI.label("", 15)
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(empty_hint)
	empty_actions = HBoxContainer.new()
	empty_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	var action_margin := UI.padding(center, 0, 9)
	action_margin.add_child(empty_actions)
	empty_actions.add_child(UI.button("Create New Project", _new_project, "create"))
	empty_actions.add_child(UI.button("Import Existing Project", _import_project, "folder"))
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 108
	workspace.add_child(sidebar)
	sidebar.add_child(HSeparator.new())
	open_button = UI.button("Open Project", func(): open_project(selected), "edit")
	sidebar.add_child(open_button)
	output_button = UI.button("Build Output", func(): log_panel.visible = not log_panel.visible; _show_log(), "output")
	sidebar.add_child(output_button)
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", UI.box(UI.LIST, 4, UI.LINE))
	log_panel.visible = false
	body.add_child(log_panel)
	var log_box := VBoxContainer.new()
	log_panel.add_child(log_box)
	var log_header := HBoxContainer.new()
	log_box.add_child(log_header)
	log_title = UI.label("Build Output", 14, UI.MUTED)
	log_header.add_child(log_title)
	UI.spacer(log_header)
	log_header.add_child(UI.button("Hide", func(): log_panel.hide()))
	log_text = TextEdit.new()
	log_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	log_text.editable = false
	log_text.custom_minimum_size.y = 104
	log_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	log_text.add_theme_font_size_override("font_size", 14)
	log_box.add_child(log_text)
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", UI.box(UI.BG, 0, Color.TRANSPARENT, 12, 4))
	layout.add_child(footer)
	var foot := HBoxContainer.new()
	footer.add_child(foot)
	UI.spacer(foot)
	env_status = UI.label("", 14, UI.MUTED)
	foot.add_child(env_status)

func _update_language_button(index: int) -> void:
	var options := language_menu.get_popup()
	language_menu.text = options.get_item_text(index)
	for i in LANGUAGES.size():
		options.set_item_checked(i, i == index)

func _change_language(index: int) -> void:
	var locale: String = LANGUAGES[index]
	TranslationServer.set_locale(locale)
	_update_language_button(index)
	store.set_value("ui", "language", locale)
	_save()
	# Static controls retranslate in place. Reformat the live status strings only.
	_update_environment()
	environment.refresh()
	_update_summary()
	_show_log()

func _save() -> void:
	store.set_value("projects", "items", projects)
	var error := store.save(settings_file)
	if error != OK:
		UI.notice(self, "Could not save settings", error_string(error))

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
	var engine := tr("Godot not configured") if environment.engine_version.is_empty() else "Godot " + environment.engine_version.get_slice(".stable", 0)
	env_status.text = engine + "    ·    " + ("godot-cpp · " + tr("SDK detected") if Projects.sdk_valid(environment.sdk_path) else tr("godot-cpp not configured"))

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
	_update_summary()
	empty.visible = listed.is_empty()
	empty_actions.get_parent().visible = projects.is_empty()
	empty_title.text = "No projects yet" if projects.is_empty() else "No matching projects"
	empty_hint.text = "Create a project or import an existing project.godot." if projects.is_empty() else "Try a different name or path."
	open_button.disabled = selected.is_empty() or not FileAccess.file_exists(Projects.settings(selected))
	output_button.disabled = selected.is_empty()
	_show_log()

func _update_summary() -> void:
	summary.text = "Scanning for projects…" if scan_thread != null else tr("Projects  ·  %d") % rows.get_child_count()

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
		UI.notice(self, "Could not open project", tr("File not found: %s") % Projects.settings(path))
		return -1
	return _launch(["--editor", "--path", path])

func open_manager() -> int:
	return _launch(["--project-manager"])

func _launch(arguments: PackedStringArray) -> int:
	var engine: String = environment.engine_path
	if not FileAccess.file_exists(engine) or not Projects.engine_supported(environment.engine_version):
		open_settings()
		environment.engine_note.text = "Select a compatible Godot editor first."
		return -1
	var pid := OS.create_process(engine, arguments)
	if pid < 0:
		UI.notice(self, "Could not launch Godot", engine)
	return pid

func _new_project() -> void:
	create_dialog = ConfirmationDialog.new()
	create_dialog.title = "Create Project"
	create_dialog.dialog_hide_on_ok = false
	create_dialog.get_ok_button().text = "Create"
	create_dialog.get_cancel_button().text = "Cancel"
	var form := VBoxContainer.new()
	create_dialog.add_child(form)
	var line := UI.field(form, "Project name")
	new_name = LineEdit.new()
	new_name.placeholder_text = "MyGame"
	new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(new_name)
	line = UI.field(form, "Parent folder (the project will have its own subfolder)")
	new_parent = LineEdit.new()
	new_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_parent.text = store.get_value("projects", "last_parent", "")
	line.add_child(new_parent)
	line.add_child(UI.button("Browse…", func(): UI.picker(create_dialog, "Select Parent Folder", FileDialog.FILE_MODE_OPEN_DIR, func(p): new_parent.text = p)))
	new_cpp = CheckBox.new()
	new_cpp.text = "Use C++ (AZGodotBuildTool)"
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
	if cpp:
		var api := Projects.new_project_api(environment.engine_version)
		var problem := Projects.cpp_api_issue(api, environment.sdk_path)
		if not problem.is_empty():
			UI.notice(create_dialog, "C++ tools are not ready", tr(problem.issue) % problem.get("args", []))
			return
		if not FileAccess.file_exists(Projects.tool_path()):
			UI.notice(create_dialog, "C++ tools are not ready", tr("Build tool not found: %s") % Projects.tool_path())
			return
	var parent := Projects.normalize(new_parent.text.strip_edges())
	var result := Projects.create(parent, new_name.text, cpp, environment.engine_version)
	if not str(result.error).is_empty():
		UI.notice(create_dialog, "Could not create project", result.error)
		return
	store.set_value("projects", "last_parent", parent)
	create_dialog.hide()
	register_paths([result.root], false)
	if cpp: request_enable(result.root)

func _import_project() -> void:
	UI.picker(self, "Import Godot Project", FileDialog.FILE_MODE_OPEN_ANY, import_path)

func import_path(path: String) -> void:
	var root := path if DirAccess.dir_exists_absolute(path) else path.get_base_dir()
	if (not DirAccess.dir_exists_absolute(path) and path.get_file() != "project.godot") or not FileAccess.file_exists(Projects.settings(root)):
		UI.notice(self, "Could not import project", "Select project.godot or the folder containing it.")
		return
	register_paths([root], true)

func _scan_projects() -> void:
	if scan_thread != null: return
	UI.picker(self, "Scan Folder", FileDialog.FILE_MODE_OPEN_DIR, scan_path)

func scan_path(path: String) -> void:
	if scan_thread != null: return
	summary.text = "Scanning for projects…"
	scan_thread = Thread.new()
	var error := scan_thread.start(Projects.scan.bind(path))
	if error != OK:
		scan_thread = null
		refresh()
		UI.notice(self, "Could not scan folder", error_string(error))
		return
	while scan_thread.is_alive():
		await get_tree().process_frame
	var paths: PackedStringArray = scan_thread.wait_to_finish()
	scan_thread = null
	if paths.is_empty():
		refresh()
		UI.notice(self, "Scan complete", "No project.godot files were found in this folder.")
	else:
		register_paths(paths, true)

func register_paths(paths: PackedStringArray, offer_cpp: bool) -> void:
	var candidates := PackedStringArray()
	for path in paths:
		var key := _key(path)
		var info := Projects.describe(key)
		if not str(info.error).is_empty():
			UI.notice(self, "Could not read project", Projects.settings(key))
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
	dialog.title = "Enable C++"
	dialog.get_cancel_button().text = "Keep as is"
	var checks: Array[CheckBox] = []
	if paths.size() == 1:
		dialog.dialog_text = tr("Enable C++ for “%s” and run its first build?\n%s") % [Projects.describe(paths[0]).name, paths[0]]
		dialog.dialog_autowrap = true
		dialog.get_ok_button().text = "Enable C++"
	else:
		dialog.get_ok_button().text = "Enable for selected projects"
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = 145
		dialog.add_child(scroll)
		var list := VBoxContainer.new()
		scroll.add_child(list)
		list.add_child(UI.label("Select projects to enable C++ for", 14, UI.MUTED))
		for path in paths:
			var check := CheckBox.new()
			check.text = "%s  ·  %s" % [Projects.describe(path).name, path]
			check.tooltip_text = path
			list.add_child(check)
			checks.append(check)
	dialog.confirmed.connect(func():
		if not _environment_ready():
			open_settings()
			environment.sdk_note.text = "After setup, click Enable C++ on the project's row."
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
		environment.sdk_note.text = "A compatible godot-cpp is required to enable C++." if not Projects.sdk_valid(environment.sdk_path) else tr("Build tool not found: %s") % Projects.tool_path()
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
				if result.has("issue"):
					problem = {"issue":result.issue, "args":result.get("args", [])}
				else:
					problem = {"issue":"Build command exited with code %s", "args":[result.code], "message":str(result.text).right(3000)}
				break
	projects[path] = problem
	projects[path]["build"] = "ready" if problem.is_empty() else "failed"
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
	log_title.text = "Build Output" if selected.is_empty() else tr("Build Output  ·  %s") % selected.get_file()
	var record: Dictionary = projects.get(selected, {})
	var text: String = logs.get(selected, record.get("message", ""))
	if record.has("issue"):
		var issue := tr(record.issue)
		if not record.get("args", []).is_empty(): issue = issue % record.args
		text = (text + "\n" + issue).strip_edges()
	log_text.text = tr("No build output yet") if text.is_empty() else text
	log_text.scroll_vertical = log_text.get_line_count()

func _exit_tree() -> void:
	if scan_thread != null and scan_thread.is_started():
		scan_thread.wait_to_finish()
