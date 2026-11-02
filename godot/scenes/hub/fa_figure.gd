extends Control
## FAの「交渉の部屋」の場面（FaView）：壁と窓、机の向こうに座る選手、机の上の名前札。
## 選手は球団カラーの帽子とユニフォームのデフォルメ（実在の顔や他のゲームの絵は使わない）。
## 表情（mood）は成功率の★で変わる：1〜2 困り顔、3 ふつう、4〜5 笑顔。

const SKIN := Color("ffdcb8")
const WALL := Color("f3ead8")
const WALL_LINE := Color("e2d3b5")
const FLOOR := Color("c9a77a")
const DESK := Color("8b5a2b")
const DESK_TOP := Color("a8703a")
const INK := Color("3a2a1e")

var team_colors: Array[Color] = [Color("888888"), Color("333333")]
var cap_text := ""
var plate_text := ""
var plate_color := NameTag.COLOR_UNKNOWN
var mood := 3


func setup(team: String, plate: String, plate_tint: Color, star_count: int) -> void:
	team_colors = GameData.team_colors(team)
	cap_text = GameData.short_name(team).substr(0, 1)
	plate_text = plate
	plate_color = plate_tint
	mood = star_count
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 40.0 or h < 40.0:
		return  # 並べ方が変わって一瞬小さくなったとき（文字の大きさが0になる）
	# 壁（腰板の線）と床
	draw_rect(Rect2(0, 0, w, h), WALL)
	draw_rect(Rect2(0, h * 0.58, w, 3), WALL_LINE)
	draw_rect(Rect2(0, h * 0.86, w, h * 0.14), FLOOR)
	# 窓（空と桟）
	var win := Rect2(w * 0.06, h * 0.08, w * 0.26, h * 0.36)
	draw_rect(win.grow(5), Color("ffffff"))
	draw_rect(win, Color("a9dcf5"))
	draw_rect(Rect2(win.position.x, win.position.y + win.size.y * 0.62, win.size.x, win.size.y * 0.38),
		Color("cfeefc"))
	draw_rect(Rect2(win.get_center().x - 2, win.position.y, 4, win.size.y), Color("ffffff"))
	draw_rect(Rect2(win.position.x, win.get_center().y - 2, win.size.x, 4), Color("ffffff"))
	# 壁の球団旗（球団カラーの三角）
	var flag := Vector2(w * 0.80, h * 0.10)
	draw_rect(Rect2(flag.x - 2, flag.y, 3, h * 0.34), Color("9a8466"))
	draw_colored_polygon(PackedVector2Array([flag, flag + Vector2(w * 0.13, h * 0.08),
		flag + Vector2(0, h * 0.16)]), team_colors[0])
	draw_colored_polygon(PackedVector2Array([flag + Vector2(0, h * 0.11), flag + Vector2(w * 0.05, h * 0.135),
		flag + Vector2(0, h * 0.16)]), team_colors[1])
	_draw_player(Vector2(w * 0.5, h * 0.40), minf(w, h) * 0.17)
	_draw_desk(w, h)


## 選手（頭・帽子・胴）。center は顔の中心、r は顔の半径
func _draw_player(center: Vector2, r: float) -> void:
	var main := team_colors[0]
	var sub := team_colors[1]
	# 胴（ユニフォーム。前立ての線と襟）
	var body := Rect2(center.x - r * 1.55, center.y + r * 0.85, r * 3.1, r * 2.4)
	_round_rect(body, r * 0.6, Color.WHITE.lerp(main, 0.12))
	draw_rect(Rect2(center.x - r * 0.06, body.position.y + r * 0.2, r * 0.12, body.size.y), sub.lerp(main, 0.3))
	draw_colored_polygon(PackedVector2Array([center + Vector2(-r * 0.5, r * 0.85), center + Vector2(r * 0.5, r * 0.85),
		center + Vector2(0, r * 1.35)]), main)
	# 首と顔
	draw_rect(Rect2(center.x - r * 0.3, center.y + r * 0.6, r * 0.6, r * 0.4), SKIN.darkened(0.08))
	draw_circle(center, r, SKIN)
	# 耳
	draw_circle(center + Vector2(-r * 0.98, r * 0.1), r * 0.18, SKIN.darkened(0.04))
	draw_circle(center + Vector2(r * 0.98, r * 0.1), r * 0.18, SKIN.darkened(0.04))
	# 帽子（上半分＋つば）と帽子の文字
	var cap := PackedVector2Array()
	for i in 21:
		var a := PI + PI * i / 20.0
		cap.append(center + Vector2(cos(a) * r * 1.04, sin(a) * r * 1.02 - r * 0.12))
	draw_colored_polygon(cap, main)
	_round_rect(Rect2(center.x - r * 1.1, center.y - r * 0.2, r * 2.2, r * 0.26), r * 0.12, main.darkened(0.25))
	draw_line(center + Vector2(0, -r * 1.12), center + Vector2(0, -r * 0.2), main.lightened(0.15), 2.0)
	if not cap_text.is_empty():
		var font := UiTheme.font(800)
		var fs := int(r * 0.62)
		var ts := font.get_string_size(cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var origin := center + Vector2(-ts.x / 2, -r * 0.42)
		draw_string_outline(font, origin, cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, sub)
		draw_string(font, origin, cap_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.text_on(main))
	# 目・ほお・口（表情は mood）
	var eye_y := center.y + r * 0.22
	for side in [-1.0, 1.0]:
		var eye := Vector2(center.x + side * r * 0.36, eye_y)
		if mood >= 4:
			_arc(eye + Vector2(0, r * 0.05), r * 0.13, PI, TAU, INK, 3.0)  # にっこり目
		else:
			draw_circle(eye, r * 0.09, INK)
		if mood <= 2:
			draw_line(eye + Vector2(-side * r * 0.16, -r * 0.24), eye + Vector2(side * r * 0.12, -r * 0.18), INK, 2.5)
		draw_circle(center + Vector2(side * r * 0.62, r * 0.45), r * 0.12, Color(1.0, 0.55, 0.55, 0.45))
	var mouth := center + Vector2(0, r * 0.58)
	if mood >= 4:
		_arc(mouth - Vector2(0, r * 0.08), r * 0.22, 0.15 * PI, 0.85 * PI, INK, 3.0)
	elif mood <= 2:
		_arc(mouth + Vector2(0, r * 0.14), r * 0.18, 1.2 * PI, 1.8 * PI, INK, 3.0)
	else:
		draw_line(mouth + Vector2(-r * 0.16, 0), mouth + Vector2(r * 0.16, 0), INK, 3.0)


## 机（天板と前板）と机の上の名前札
func _draw_desk(w: float, h: float) -> void:
	var top := Rect2(w * 0.08, h * 0.66, w * 0.84, h * 0.07)
	_round_rect(top, 4, DESK_TOP)
	draw_rect(Rect2(w * 0.11, top.end.y, w * 0.78, h * 0.86 - top.end.y), DESK)
	draw_rect(Rect2(w * 0.11, top.end.y, w * 0.78, 3), DESK.darkened(0.3))
	if plate_text.is_empty():
		return
	var font := UiTheme.font(800)
	var fs := int(h * 0.075)
	var ts := font.get_string_size(plate_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var plate := Rect2(w * 0.5 - ts.x / 2 - 14, top.position.y - h * 0.035, ts.x + 28, fs + 12)
	_round_rect(Rect2(plate.position + Vector2(0, 3), plate.size), 6, Color(0, 0, 0, 0.25))
	_round_rect(plate, 6, plate_color)
	draw_string(font, Vector2(plate.position.x + 14, plate.position.y + 6 + font.get_ascent(fs)), plate_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)


func _round_rect(rect: Rect2, radius: float, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(int(radius))
	draw_style_box(s, rect)


func _arc(center: Vector2, radius: float, from: float, to: float, color: Color, width: float) -> void:
	draw_arc(center, radius, from, to, 16, color, width, true)
