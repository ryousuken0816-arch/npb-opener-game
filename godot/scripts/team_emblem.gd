class_name TeamEmblem
extends Control
## 球団の丸いエンブレム（ロゴ画像の代わり。球団カラーの円に略称）。上半分にツヤ、文字は縁取り。

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
	draw_circle(center + Vector2(0, r * 0.06), r * 0.74, palette.main.darkened(0.08))
	draw_circle(center - Vector2(0, r * 0.03), r * 0.74, palette.main.lightened(0.06))
	# 上半分のツヤ（横長の半透明の楕円、上ほど白い）
	var shine := PackedVector2Array()
	var shine_colors := PackedColorArray()
	for i in 25:
		var a := PI + PI * i / 24.0
		var pt := center + Vector2(cos(a) * r * 0.66, sin(a) * r * 0.62 - r * 0.02)
		shine.append(pt)
		var t := clampf((center.y - pt.y) / (r * 0.6), 0, 1)
		shine_colors.append(Color(1, 1, 1, lerpf(0.05, 0.42, t)))
	draw_polygon(shine, shine_colors)
	if label.is_empty():
		return
	var font := UiTheme.font(800)
	var font_size := int(minf(r * 0.62, r * 1.35 / label.length()))
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2
	var origin := Vector2(center.x - text_size.x / 2, baseline)
	var outline := UiTheme.outline_for(palette.on_main, palette.main)
	draw_string_outline(font, origin + Vector2(0, r * 0.03), label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size, int(r * 0.1), Color(0, 0, 0, 0.18))
	draw_string_outline(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(r * 0.08),
		outline)
	draw_string(font, origin, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, palette.on_main)
