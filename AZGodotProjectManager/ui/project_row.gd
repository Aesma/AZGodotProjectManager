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
	custom_minimum_size.y = 72
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style()
	mouse_entered.connect(func(): _style(true))
	mouse_exited.connect(func(): _style())
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 12)
	add_child(line)
	var tile := PanelContainer.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.custom_minimum_size = Vector2(64, 64)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.add_theme_stylebox_override("panel", UI.box(Color("#353d50"), 6, Color("#252b37"), 5, 5))
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
	meta.add_theme_constant_override("separation", 9)
	line.add_child(meta)
	var title := UI.label(info.name, 17)
	title.theme_type_variation = &"ManagerHeading"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_child(title)
	var location := HBoxContainer.new()
	location.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(location)
	var folder := TextureRect.new()
	folder.texture = UI.icon("folder")
	folder.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	folder.modulate = UI.MUTED
	folder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location.add_child(folder)
	var path := UI.label(root, 15, UI.MUTED)
	path.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	location.add_child(path)
	tooltip_text = root
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 164
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 7)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(right)
	if state == "plain" or state == "native":
		toggle = CheckBox.new()
		toggle.text = "Enable C++" if state == "plain" else "Set up C++ build"
		toggle.size_flags_horizontal = Control.SIZE_SHRINK_END
		toggle.mouse_filter = Control.MOUSE_FILTER_STOP
		toggle.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toggle.pressed.connect(func(): enable_requested.emit(root))
		right.add_child(toggle)
	elif state == "failed":
		var retry := UI.button("C++ build failed · Retry", func(): enable_requested.emit(root))
		retry.size_flags_horizontal = Control.SIZE_SHRINK_END
		retry.add_theme_color_override("font_color", UI.WARN)
		right.add_child(retry)
	else:
		var captions := {"enabled":"✓  C++ enabled", "queued":"C++ build queued…", "building":"Enabling C++…", "missing":"Project unavailable"}
		var status := UI.label(captions.get(state, state), 14, UI.GREEN if state == "enabled" else UI.MUTED)
		status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.add_child(status)
	var date := Time.get_datetime_string_from_unix_time(info.time + Time.get_time_zone_from_system().bias * 60, true).left(16) if info.time else ""
	var details := UI.label("   ".join(PackedStringArray([info.version, date])).strip_edges(), 14, UI.MUTED)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(details)

func _style(hover := false) -> void:
	var fill := Color("#373737") if active else (Color("#2d2d2d") if hover else UI.LIST)
	add_theme_stylebox_override("panel", UI.box(fill, 4, Color.TRANSPARENT, 9, 4))

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
