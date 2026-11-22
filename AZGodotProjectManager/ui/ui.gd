extends RefCounted

const BG := Color("#141414")
const SURFACE := Color("#282828")
const LIST := Color("#202020")
const RAISED := Color("#414141")
const LINE := Color("#505050")
const INK := Color("#dedede")
const MUTED := Color("#aaaeb3")
const BLUE := Color("#70b4ff")
const GREEN := Color("#9bcbb4")
const WARN := Color("#edbd87")
static var _icons: Dictionary[String, Texture2D] = {}

static func display_scale(screen: int) -> float:
	var dpi := DisplayServer.screen_get_dpi(screen)
	match OS.get_name():
		"Windows":
			return maxf(1.0, dpi / 96.0)
		"macOS":
			return maxf(1.0, DisplayServer.screen_get_scale(screen))
		"Linux":
			if DisplayServer.get_name() == "Wayland":
				return maxf(1.0, DisplayServer.screen_get_scale(screen))
			var size := DisplayServer.screen_get_size(screen)
			var pixels := mini(size.x, size.y)
			if dpi >= 192 and pixels >= 1400: return 2.0
			if pixels >= 1700: return 1.5
	return 1.0

# Small monochrome toolbar icons are rasterized by Godot at the display's DPI.
static func icon(kind: String) -> Texture2D:
	if _icons.has(kind): return _icons[kind]
	var paths := {
		"create": "M8 2v12M2 8h12",
		"folder": "M1.5 12.5V3h5l2 2h5v2 M1.5 13h11l2-6h-11z",
		"search": "M11 11l3.5 3.5 M12 7a5 5 0 1 1-10 0a5 5 0 0 1 10 0z",
		"projects": "M6.5 3h8 M6.5 8h8 M6.5 13h8 M2 3h1 M2 8h1 M2 13h1",
		"edit": "M2 14l1-4L11.5 1.5l3 3L6 13z M9.5 3.5l3 3",
		"output": "M1.5 3h13v10h-13z M4 6l2 2-2 2 M8 10h3",
		"settings": "M4 1v4m0 5v5 M12 1v7m0 5v2 M2 5h4v4H2z M10 8h4v4h-4z",
		"launch": "M8 2h6v6 M14 2L7 9 M6 4H2v10h10v-4",
	}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16"><path d="%s" fill="none" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>'
	_icons[kind] = DPITexture.create_from_string(svg % paths[kind])
	return _icons[kind]

static func box(color: Color, radius := 5, border := Color.TRANSPARENT, x := 12, y := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.border_color = border
	style.set_border_width_all(0 if border.a == 0 else 1)
	style.content_margin_left = x
	style.content_margin_right = x
	style.content_margin_top = y
	style.content_margin_bottom = y
	return style

static func theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "PingFang SC", "Noto Sans CJK SC", "Segoe UI", "Arial"])
	font.hinting = TextServer.HINTING_NORMAL
	t.default_font = font
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	var heading_font := font.duplicate() as SystemFont
	heading_font.font_weight = 650
	t.set_type_variation("ManagerHeading", "Label")
	t.set_font("font", "ManagerHeading", heading_font)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(RAISED, 4, LINE, 8, 5))
		t.set_stylebox("hover", type, box(Color("#505050"), 4, Color("#646464"), 8, 5))
		t.set_stylebox("pressed", type, box(Color("#383e45"), 4, BLUE, 8, 5))
		t.set_stylebox("disabled", type, box(Color("#353535"), 4, Color.TRANSPARENT, 8, 5))
		t.set_color("font_color", type, INK)
		t.set_constant("h_separation", type, 5)
	t.set_stylebox("normal", "LineEdit", box(Color("#1d1d1d"), 4, Color.TRANSPARENT, 8, 5))
	t.set_stylebox("normal", "CheckBox", box(Color.TRANSPARENT, 4, Color.TRANSPARENT, 5, 3))
	t.set_stylebox("hover", "CheckBox", box(Color("#364452"), 4, Color.TRANSPARENT, 5, 3))
	for checked in [false, true]:
		var image := Image.create_empty(18, 18, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		image.fill_rect(Rect2i(1, 1, 16, 16), BLUE if checked else Color("#9aa7b5"))
		image.fill_rect(Rect2i(3, 3, 12, 12), Color("#47769a") if checked else Color("#22272c"))
		if checked:
			for x in 4: image.fill_rect(Rect2i(4 + x, 8 + x, 2, 2), Color.WHITE)
			for x in 7: image.fill_rect(Rect2i(7 + x, 11 - x, 2, 2), Color.WHITE)
		t.set_icon("checked" if checked else "unchecked", "CheckBox", ImageTexture.create_from_image(image))
	t.set_stylebox("panel", "PopupMenu", box(SURFACE, 5, LINE))
	t.set_stylebox("panel", "AcceptDialog", box(SURFACE, 5, LINE, 18, 16))
	t.set_constant("separation", "HBoxContainer", 5)
	t.set_constant("separation", "VBoxContainer", 6)
	return t

static func label(value: String, size := 15, color := INK) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func button(value: String, callback: Callable, icon_name := "") -> Button:
	var b := Button.new()
	b.text = value
	b.custom_minimum_size.y = 34
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	if not icon_name.is_empty():
		b.icon = icon(icon_name)
	return b

static func padding(parent: Control, x: int, y: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, x)
	for side in ["top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, y)
	parent.add_child(m)
	return m

static func spacer(parent: Container) -> Control:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(space)
	return space

static func field(parent: VBoxContainer, caption: String) -> HBoxContainer:
	parent.add_child(label(caption, 14, MUTED))
	var line := HBoxContainer.new()
	parent.add_child(line)
	return line

static func notice(parent: Node, caption: String, message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = caption
	dialog.dialog_text = message
	dialog.dialog_autowrap = true
	dialog.get_ok_button().text = "OK"
	parent.add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())
	dialog.popup_centered(Vector2i(490, 190))

static func picker(parent: Node, caption: String, mode: FileDialog.FileMode, callback: Callable, filters := PackedStringArray()) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.title = caption
	dialog.filters = filters
	dialog.show_hidden_files = true
	var home := OS.get_environment("USERPROFILE" if OS.get_name() == "Windows" else "HOME")
	if DirAccess.dir_exists_absolute(home):
		dialog.current_dir = home
	dialog.file_selected.connect(callback)
	dialog.dir_selected.connect(callback)
	parent.add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())
	dialog.popup_centered_clamped(Vector2i(830, 560), 0.86)
	return dialog
