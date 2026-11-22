extends Control

var folder := false

func _draw() -> void:
	var unit := minf(size.x, size.y) / 32.0
	draw_set_transform((size - Vector2.ONE * 32.0 * unit) / 2.0, 0, Vector2.ONE * unit)
	var blue := Color("#87bcdf")
	if folder:
		draw_colored_polygon(PackedVector2Array([Vector2(3, 9), Vector2(12, 9), Vector2(15, 12), Vector2(28, 12), Vector2(28, 24), Vector2(3, 24)]), Color("#517599"))
		draw_colored_polygon(PackedVector2Array([Vector2(5, 14), Vector2(30, 14), Vector2(26, 25), Vector2(3, 25)]), blue)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(2, 10), Vector2(16, 3), Vector2(30, 10), Vector2(16, 17)]), Color("#9cccef"))
		draw_colored_polygon(PackedVector2Array([Vector2(2, 13), Vector2(14, 19), Vector2(14, 29), Vector2(2, 23)]), Color("#6299c3"))
		draw_colored_polygon(PackedVector2Array([Vector2(18, 19), Vector2(30, 13), Vector2(30, 23), Vector2(18, 29)]), Color("#46789e"))
