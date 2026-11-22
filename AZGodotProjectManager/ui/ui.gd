extends RefCounted

const BG := Color("#202328")
const SURFACE := Color("#282c32")
const RAISED := Color("#343941")
const LINE := Color("#40454e")
const INK := Color("#e7e9ee")
const MUTED := Color("#a4acb9")
const BLUE := Color("#91c8f7")
const GREEN := Color("#9bcbb4")
const WARN := Color("#edbd87")

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
	t.default_font = font
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	for type in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, box(RAISED, 5, LINE))
		t.set_stylebox("hover", type, box(Color("#414955"), 5, Color("#586575")))
		t.set_stylebox("pressed", type, box(Color("#35495b"), 5, Color("#6289a9")))
		t.set_stylebox("disabled", type, box(Color("#2e3237")))
		t.set_color("font_color", type, INK)
	t.set_stylebox("normal", "LineEdit", box(Color("#1d2025"), 5, LINE))
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
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 8)
	return t

static func label(value: String, size := 15, color := INK) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

static func button(value: String, callback: Callable, accent := false) -> Button:
	var b := Button.new()
	b.text = value
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(callback)
	if accent:
		b.add_theme_stylebox_override("normal", box(Color("#426d92"), 5, Color("#5a87ad")))
		b.add_theme_stylebox_override("hover", box(Color("#537fa4"), 5, Color("#76a4c8")))
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
	dialog.get_ok_button().text = "确定"
	parent.add_child(dialog)
	dialog.visibility_changed.connect(func():
		if not dialog.visible: dialog.queue_free())
	dialog.popup_centered(Vector2i(490, 190))

static func picker(parent: Node, caption: String, mode: FileDialog.FileMode, callback: Callable, filters := PackedStringArray()) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.title = caption
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
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
