class_name TeamBackground
extends Control
## 明るい背景。球団カラーの薄いグラデーションに、斜めの帯を重ねる。

var palette: UiTheme.Palette = UiTheme.neutral_palette()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_palette(p: UiTheme.Palette) -> void:
	palette = p
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var p := palette
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([p.bg_top, p.bg_top, p.bg_bottom, p.bg_bottom]))
	# 左下から右上へ流れる帯（メイン色・サブ色・白のハイライト）
	_band(0.62, 0.30, 0.16, _alpha(p.main, 0.10))
	_band(0.80, 0.42, 0.10, _alpha(p.main, 0.16))
	_band(0.93, 0.52, 0.035, _alpha(p.sub, 0.15))
	_band(0.47, 0.18, 0.03, Color(1, 1, 1, 0.55))
	# 上端の球団カラーのライン
	draw_rect(Rect2(0, 0, w, 6), p.main)
	draw_rect(Rect2(0, 6, w, 3), _alpha(p.sub, 0.8))


## 左端の高さ y_left から右端の高さ y_right へ斜めに横切る帯（割合で指定）
func _band(y_left: float, y_right: float, thickness: float, color: Color) -> void:
	var w := size.x
	var h := size.y
	var t := thickness * h
	draw_polygon(PackedVector2Array([
		Vector2(0, y_left * h), Vector2(w, y_right * h),
		Vector2(w, y_right * h + t), Vector2(0, y_left * h + t),
	]), PackedColorArray([color]))


func _alpha(c: Color, a: float) -> Color:
	return Color(c, a)
