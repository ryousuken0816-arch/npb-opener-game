class_name TeamEmblem
extends Control
## 球団の丸いエンブレム（ロゴ画像の代わり。球団カラーの円に略称）。

var palette: UiTheme.Palette = UiTheme.neutral_palette()
var label := ""


func setup(p: UiTheme.Palette, text: String) -> void:
	palette = p
	label = text
	queue_redraw()


func _draw() -> void:
	var center := size / 2
	var r := minf(size.x, size.y) / 2
	draw_circle(center + Vector2(0, r * 0.04), r, Color(0, 0, 0, 0.18))
	draw_circle(center, r, Color.WHITE)
	draw_circle(center, r * 0.93, palette.sub)
	draw_circle(center, r * 0.85, Color.WHITE)
	draw_circle(center, r * 0.80, palette.main)
	if label.is_empty():
		return
	var font := UiTheme.font(800)
	var font_size := int(minf(r * 0.62, r * 1.35 / label.length()))
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2
	draw_string(font, Vector2(center.x - text_size.x / 2, baseline), label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, palette.on_main)
