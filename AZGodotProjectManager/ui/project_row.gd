extends PanelContainer

const UI = preload("res://ui/ui.gd")
const Mark = preload("res://ui/mark.gd")
signal selected(root: String)
signal open_requested(root: String)
signal enable_requested(root: String)
var root: String
var active := false
var toggle: CheckBox

func setup(info: Dictionary, state: String, current: bool) -> void:
	root = info.root
	active = current
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size.y = 80
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style()
	mouse_entered.connect(func(): _style(true))
	mouse_exited.connect(func(): _style())
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 14)
	add_child(line)
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(52, 52)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override("panel", UI.box(Color("#343f4f"), 8, Color("#465567"), 9, 9))
	line.add_child(tile)
	var picture := Image.new()
	if not str(info.icon).is_empty() and FileAccess.file_exists(info.icon) and picture.load(info.icon) == OK:
		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = ImageTexture.create_from_image(picture)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(icon)
	else:
		var symbol := Mark.new()
		symbol.folder = true
		symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(symbol)
	var meta := VBoxContainer.new()
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 4)
	line.add_child(meta)
	var title := UI.label(info.name, 18)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_child(title)
	var path := UI.label(root, 13, UI.MUTED)
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_child(path)
	tooltip_text = root
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 193
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(right)
	if state == "plain" or state == "native":
		toggle = CheckBox.new()
		toggle.text = "启用 C++" if state == "plain" else "接入 C++ 构建"
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
		toggle.mouse_filter = Control.MOUSE_FILTER_STOP
		toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toggle.pressed.connect(func(): enable_requested.emit(root))
		right.add_child(toggle)
	elif state == "failed":
		var retry := UI.button("C++ 构建失败 · 重试", func(): enable_requested.emit(root))
		retry.size_flags_horizontal = Control.SIZE_SHRINK_END
		retry.add_theme_color_override("font_color", UI.WARN)
		right.add_child(retry)
	else:
		var captions := {"enabled":"✓  已启用 C++", "queued":"等待启用 C++…", "building":"正在启用 C++…", "missing":"项目不可用"}
		var status := UI.label(captions.get(state, state), 14, UI.GREEN if state == "enabled" else UI.MUTED)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(status)
	var date := Time.get_datetime_string_from_unix_time(info.time + Time.get_time_zone_from_system().bias * 60, true).left(16) if info.time else ""
	var details := UI.label("   ".join(PackedStringArray([info.version, date])).strip_edges(), 12, UI.MUTED)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(details)

func _style(hover := false) -> void:
	var fill := Color("#35404c") if active else (Color("#30363d") if hover else Color("#282c32"))
	add_theme_stylebox_override("panel", UI.box(fill, 5, Color("#536b80") if active else Color.TRANSPARENT, 14, 10))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		selected.emit(root)
		if event.double_click:
			open_requested.emit(root)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		open_requested.emit(root)
		accept_event()
