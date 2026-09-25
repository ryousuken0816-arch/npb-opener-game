class_name TeamBackground
extends Control
## 明るい背景（docs/references/README.md「UI全体の質感アップ」3）。画像は使わずコードで描く：
## 球団カラーの空（上ほど色が濃いグラデーション）に斜めの細いストライプ、スタジアムの照明の光、
## 左下から右上へ流れる帯、下側に芝生（刈り込みの縞と白いライン）。黒基調にはしない。

## 芝生の上端（画面の高さに対する割合。左端→右端でゆるく傾ける）
const TURF_TOP_LEFT := 0.74
const TURF_TOP_RIGHT := 0.66
const TURF_LIGHT := Color("8fd16f")
const TURF_DARK := Color("5fae4c")
const STRIPE_GAP := 22.0
## 照明の光（中心の x・y を割合で、半径を高さに対する割合で）
const LIGHTS := [[0.12, -0.05, 0.55], [0.55, -0.12, 0.5], [0.95, 0.0, 0.6]]

var palette: UiTheme.Palette = UiTheme.neutral_palette()

var _light_texture: GradientTexture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.75))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.35, Color(1, 1, 1, 0.3))
	_light_texture = GradientTexture2D.new()
	_light_texture.gradient = g
	_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_texture.fill_from = Vector2(0.5, 0.5)
	_light_texture.fill_to = Vector2(1.0, 0.5)
	_light_texture.width = 256
	_light_texture.height = 256


func set_palette(p: UiTheme.Palette) -> void:
	palette = p
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var p := palette
	# 空：上ほど球団カラーが濃い（それでも明るい）グラデーション
	var sky_top := p.main.lerp(Color.WHITE, 0.52)
	var sky_mid := p.main.lerp(Color.WHITE, 0.82)
	draw_polygon(
		PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h * 0.7), Vector2(0, h * 0.7)]),
		PackedColorArray([sky_top, sky_top, sky_mid, sky_mid]))
	draw_rect(Rect2(0, h * 0.7, w, h * 0.3), sky_mid)
	_stripes(w, h)
	# スタジアムの照明の光
	if _light_texture:
		for light: Array in LIGHTS:
			var r: float = light[2] * h
			var c := Vector2(light[0] * w, light[1] * h)
			draw_texture_rect(_light_texture, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false)
	# 左下から右上へ流れる帯（メイン色・サブ色・白のハイライト）
	_band(0.60, 0.26, 0.15, Color(p.main, 0.13))
	_band(0.78, 0.40, 0.09, Color(p.main, 0.2))
	_band(0.90, 0.50, 0.03, Color(p.sub, 0.22))
	_band(0.46, 0.15, 0.025, Color(1, 1, 1, 0.6))
	_turf(w, h)
	# 上端の球団カラーのライン（ツヤ付き）
	draw_rect(Rect2(0, 0, w, 7), p.main)
	draw_rect(Rect2(0, 0, w, 3), Color(1, 1, 1, 0.3))
	draw_rect(Rect2(0, 7, w, 3), Color(p.sub, 0.85))


## 斜めの細いストライプ（ごく薄い白）
func _stripes(w: float, h: float) -> void:
	var color := Color(1, 1, 1, 0.16)
	var x := -h
	while x < w:
		draw_polygon(PackedVector2Array([
			Vector2(x, h), Vector2(x + h * 0.6, 0), Vector2(x + h * 0.6 + 7, 0), Vector2(x + 7, h),
		]), PackedColorArray([color]))
		x += STRIPE_GAP


## 芝生：刈り込みの縞（手前ほど太い）＋上端の土の線＋白いライン
func _turf(w: float, h: float) -> void:
	var top_l := TURF_TOP_LEFT * h
	var top_r := TURF_TOP_RIGHT * h
	draw_polygon(
		PackedVector2Array([Vector2(0, top_l), Vector2(w, top_r), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([TURF_LIGHT, TURF_LIGHT, TURF_DARK, TURF_DARK]))
	# 縞：画面の上の方にある消失点から放射状に
	var vanish := Vector2(w * 0.5, -h * 1.4)
	var count := 16
	for i in count:
		if i % 2 == 1:
			continue
		var x0 := w * (float(i) / count) * 1.6 - w * 0.3
		var x1 := w * (float(i + 1) / count) * 1.6 - w * 0.3
		var a := _on_turf_top(vanish, Vector2(x0, h))
		var b := _on_turf_top(vanish, Vector2(x1, h))
		draw_polygon(PackedVector2Array([a, b, Vector2(x1, h), Vector2(x0, h)]),
			PackedColorArray([Color(1, 1, 1, 0.1)]))
	# 芝生の上端（土のライン）と、ファウルラインのような白い線
	draw_line(Vector2(0, top_l), Vector2(w, top_r), Color("d9b98a"), 5.0, true)
	draw_line(Vector2(0, top_l + 3), Vector2(w, top_r + 3), Color(1, 1, 1, 0.35), 1.5, true)
	draw_line(Vector2(w * 0.08, h), _on_turf_top(Vector2(w * 0.08, h), Vector2(w * 0.62, top_l)),
		Color(1, 1, 1, 0.75), 4.0, true)


## 点 from から点 to の方向へ伸ばした直線が芝生の上端と交わる点（to が芝生の上端より下なら上端まで伸ばす）
func _on_turf_top(from: Vector2, to: Vector2) -> Vector2:
	var top_l := TURF_TOP_LEFT * size.y
	var top_r := TURF_TOP_RIGHT * size.y
	var hit: Variant = Geometry2D.line_intersects_line(from, to - from, Vector2(0, top_l),
		Vector2(size.x, top_r - top_l))
	return hit if hit != null else to


## 左端の高さ y_left から右端の高さ y_right へ斜めに横切る帯（割合で指定）
func _band(y_left: float, y_right: float, thickness: float, color: Color) -> void:
	var w := size.x
	var h := size.y
	var t := thickness * h
	draw_polygon(PackedVector2Array([
		Vector2(0, y_left * h), Vector2(w, y_right * h),
		Vector2(w, y_right * h + t), Vector2(0, y_left * h + t),
	]), PackedColorArray([color]))
