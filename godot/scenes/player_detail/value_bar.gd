class_name ValueBar
extends Control
## 選手詳細の能力の棒（0〜1、ランクの色）

var value := 0.0
var color := Color("9aa3ad")

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UiTheme.box(Color("e3e8ee"), int(size.y / 2)), r)
	if value > 0.0:
		var fill := Rect2(Vector2.ZERO, Vector2(maxf(size.y, size.x * clampf(value, 0.0, 1.0)), size.y))
		draw_style_box(UiTheme.box(color, int(size.y / 2)), fill)
		draw_rect(Rect2(fill.position + Vector2(size.y / 2, 2), Vector2(maxf(0.0, fill.size.x - size.y),
			size.y * 0.25)), Color(1, 1, 1, 0.35))
