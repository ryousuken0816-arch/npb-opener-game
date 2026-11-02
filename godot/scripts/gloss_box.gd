class_name GlossBox
extends StyleBox
## パワプロ風の立体的な StyleBox（docs/references/README.md「UI全体の質感アップ」）。
## 縦グラデーションの面＋上半分のツヤ＋太い縁取り＋下側の厚み（濃い色の縁）＋影。
##
## 縁取り・角丸・影・斜め（skew）は内部の StyleBoxFlat に任せ、その上に面のグラデーションとツヤを
## 頂点カラー付きのポリゴンで重ねる。プロパティ名は StyleBoxFlat に合わせてある
## （bg_color / border_color / set_border_width_all / set_corner_radius_all / shadow_* / skew）。
## pressed = true で「押して沈んだ」見た目（厚みがなくなり面が下がる）。

## 角丸の1つの角を何分割の折れ線で近似するか
const ARC_STEPS := 6

## 面の色（グラデーションの中間色）
var bg_color := Color.WHITE:
	set(v):
		bg_color = v
		_sync()
var border_color := Color.BLACK:
	set(v):
		border_color = v
		_sync()
## 下側の厚み（面の下にのぞく濃い色の帯の高さ）
var depth := 0:
	set(v):
		depth = v
		_sync()
## 面の上下の明暗差（0 でべた塗り）
var gradient := 0.18:
	set(v):
		gradient = v
		emit_changed()
## 上半分のツヤの強さ（0 でツヤなし）
var gloss := 0.45:
	set(v):
		gloss = v
		emit_changed()
var pressed := false:
	set(v):
		pressed = v
		_sync()
var draw_center := true:
	set(v):
		draw_center = v
		_sync()
var skew := Vector2.ZERO:
	set(v):
		skew = v
		_sync()
var shadow_color := Color(0, 0, 0, 0.25):
	set(v):
		shadow_color = v
		_sync()
var shadow_size := 0:
	set(v):
		shadow_size = v
		_sync()
var shadow_offset := Vector2(0, 2):
	set(v):
		shadow_offset = v
		_sync()
var border_width_left := 0:
	set(v):
		border_width_left = v
		_sync()
var border_width_top := 0:
	set(v):
		border_width_top = v
		_sync()
var border_width_right := 0:
	set(v):
		border_width_right = v
		_sync()
var border_width_bottom := 0:
	set(v):
		border_width_bottom = v
		_sync()
var corner_radius_top_left := 0:
	set(v):
		corner_radius_top_left = v
		_sync()
var corner_radius_top_right := 0:
	set(v):
		corner_radius_top_right = v
		_sync()
var corner_radius_bottom_right := 0:
	set(v):
		corner_radius_bottom_right = v
		_sync()
var corner_radius_bottom_left := 0:
	set(v):
		corner_radius_bottom_left = v
		_sync()

var _flat := StyleBoxFlat.new()


func _init() -> void:
	_flat.anti_aliasing = true
	_sync()


func set_border_width_all(width: int) -> void:
	border_width_left = width
	border_width_top = width
	border_width_right = width
	border_width_bottom = width


func set_corner_radius_all(radius: int) -> void:
	corner_radius_top_left = radius
	corner_radius_top_right = radius
	corner_radius_bottom_right = radius
	corner_radius_bottom_left = radius


## 同じ見た目の別インスタンス（duplicate() はスクリプトの変数を写さないことがあるので手で写す）
func copy() -> GlossBox:
	var s := GlossBox.new()
	for prop in ["bg_color", "border_color", "depth", "gradient", "gloss", "pressed", "draw_center",
			"skew", "shadow_color", "shadow_size", "shadow_offset",
			"border_width_left", "border_width_top", "border_width_right", "border_width_bottom",
			"corner_radius_top_left", "corner_radius_top_right",
			"corner_radius_bottom_right", "corner_radius_bottom_left",
			"content_margin_left", "content_margin_top", "content_margin_right", "content_margin_bottom"]:
		s.set(prop, get(prop))
	return s


## 押したときの見た目（面が厚みのぶん下がる。文字も一緒に下げる）
func pressed_copy() -> GlossBox:
	var s := copy()
	s.pressed = true
	s.content_margin_top = content_margin_top + depth
	s.content_margin_bottom = maxf(content_margin_bottom - depth, 0)
	return s


## 下側の縁（厚み）の色
func lip_color() -> Color:
	return Color(bg_color.darkened(0.35), bg_color.a)


func _sync() -> void:
	if _flat == null:
		return
	var d := 0 if pressed else depth
	_flat.bg_color = lip_color() if d > 0 else bg_color
	_flat.draw_center = draw_center
	_flat.border_color = border_color
	_flat.border_width_left = border_width_left
	_flat.border_width_top = border_width_top
	_flat.border_width_right = border_width_right
	_flat.border_width_bottom = border_width_bottom
	_flat.corner_radius_top_left = corner_radius_top_left
	_flat.corner_radius_top_right = corner_radius_top_right
	_flat.corner_radius_bottom_right = corner_radius_bottom_right
	_flat.corner_radius_bottom_left = corner_radius_bottom_left
	_flat.skew = skew
	_flat.shadow_color = shadow_color
	_flat.shadow_size = 0 if pressed else shadow_size
	_flat.shadow_offset = shadow_offset
	emit_changed()


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	_flat.draw(to_canvas_item, _body_rect(rect))
	if not draw_center or bg_color.a <= 0.0:
		return
	var face := face_rect(rect)
	if face.size.x <= 2 or face.size.y <= 2:
		return
	var radii := face_radii()
	var center_y := rect.position.y + rect.size.y * 0.5
	paint(to_canvas_item, face, radii, bg_color.lightened(gradient), bg_color.darkened(gradient * 0.6),
		skew.x, center_y)
	if gloss > 0.0:
		shine(to_canvas_item, face, radii, gloss * (0.75 if pressed else 1.0) * bg_color.a,
			skew.x, center_y)


## 押している間は全体を厚みのぶん下げる
func _body_rect(rect: Rect2) -> Rect2:
	var r := rect
	if pressed:
		r.position.y += depth
		r.size.y -= depth
	return r


## 縁取りと厚みの内側の面（グラデーションとツヤを描く範囲）
func face_rect(rect: Rect2) -> Rect2:
	var r := _body_rect(rect)
	var d := 0 if pressed else depth
	return Rect2(
		r.position.x + border_width_left, r.position.y + border_width_top,
		r.size.x - border_width_left - border_width_right,
		r.size.y - border_width_top - border_width_bottom - d)


## 面の角丸（左上・右上・右下・左下）
func face_radii() -> Array:
	return [
		maxi(corner_radius_top_left - maxi(border_width_left, border_width_top), 0),
		maxi(corner_radius_top_right - maxi(border_width_right, border_width_top), 0),
		maxi(corner_radius_bottom_right - maxi(border_width_right, border_width_bottom), 0),
		maxi(corner_radius_bottom_left - maxi(border_width_left, border_width_bottom), 0),
	]


## 面 face の上半分にツヤ（白の半透明を上から下へ薄く）を重ねる。名前札の2色の面などにも使う
static func shine(ci: RID, face: Rect2, radii: Array, strength: float, skew_x := 0.0,
		center_y := NAN) -> void:
	var inset := maxf(minf(face.size.x, face.size.y) * 0.06, 1.5)
	var area := Rect2(face.position.x + inset, face.position.y + 1.0,
		face.size.x - inset * 2, face.size.y * 0.46)
	var shine_radii := [
		maxi(int(radii[0]) - 1, 0), maxi(int(radii[1]) - 1, 0),
		mini(4, int(radii[2])), mini(4, int(radii[3])),
	]
	paint(ci, area, shine_radii, Color(1, 1, 1, 0.62 * strength), Color(1, 1, 1, 0.1 * strength),
		skew_x, center_y)


func _fill(ci: RID, rect: Rect2, area: Rect2, radii: Array, top: Color, bottom: Color) -> void:
	paint(ci, area, radii, top, bottom, skew.x, rect.position.y + rect.size.y * 0.5)


## 角丸四角形 area を上下グラデーションで塗る。skew_x は StyleBoxFlat の skew と同じ向き（center_y が中心）
static func paint(ci: RID, area: Rect2, radii: Array, top: Color, bottom: Color, skew_x := 0.0,
		center_y := NAN) -> void:
	if area.size.x < 2.0 or area.size.y < 2.0:
		return  # 細すぎる（多角形にできない）
	var points := PackedVector2Array()
	# 角丸の半径が辺の半分と同じだと、となり合う点が重なって多角形にできない（重なった点は除く）
	for p: Vector2 in _rounded_rect(area, radii):
		if points.is_empty() or not p.is_equal_approx(points[points.size() - 1]):
			points.append(p)
	if points.size() > 1 and points[0].is_equal_approx(points[points.size() - 1]):
		points.remove_at(points.size() - 1)
	if points.size() < 3:
		return
	var colors := PackedColorArray()
	colors.resize(points.size())
	var cy := center_y if not is_nan(center_y) else area.position.y + area.size.y * 0.5
	for i in points.size():
		var t := clampf((points[i].y - area.position.y) / area.size.y, 0.0, 1.0)
		colors[i] = top.lerp(bottom, t)
		if skew_x != 0.0:
			points[i].x -= skew_x * (points[i].y - cy)
	RenderingServer.canvas_item_add_polygon(ci, points, colors)
	# 縁を1px のなめらかな線でなぞってギザギザを隠す
	var outline := points.duplicate()
	outline.append(points[0])
	var outline_colors := colors.duplicate()
	outline_colors.append(colors[0])
	RenderingServer.canvas_item_add_polyline(ci, outline, outline_colors, 1.0, true)


static func _rounded_rect(area: Rect2, radii: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var max_r := minf(area.size.x, area.size.y) * 0.5
	var corners := [
		[area.position + Vector2(0, 0), Vector2(1, 1), PI],             # 左上（180°→270°）
		[area.position + Vector2(area.size.x, 0), Vector2(-1, 1), PI * 1.5],   # 右上
		[area.end, Vector2(-1, -1), 0.0],                                # 右下
		[area.position + Vector2(0, area.size.y), Vector2(1, -1), PI * 0.5],  # 左下
	]
	for i in 4:
		var r := minf(float(radii[i]), max_r)
		var corner: Vector2 = corners[i][0]
		if r <= 0.5:
			pts.append(corner)
			continue
		var dir: Vector2 = corners[i][1]
		var c := corner + dir * r
		var start: float = corners[i][2]
		for s in ARC_STEPS + 1:
			var ang := start + PI * 0.5 * s / ARC_STEPS
			pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	return pts
