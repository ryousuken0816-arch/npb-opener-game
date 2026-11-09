class_name PitchChart
extends Control
## 捕手から見た持ち球の8方向（作業79の PitchArsenal を、選手詳細の投手能力でこう見せる）。
## 上＝ストレート、右＝スライダー側、左＝シュート側、下＝落ちる球。斜めはカーブ・カット・シンカーなど。
## 各方向は7マス。塗った数＝変化量（1〜7）。ストレートだけは持ち球に無いので、球速のランクを同じ7マスに置いた目安
## （S=7 … G=1。変化量ではない）。決め球は金色の縁。データは pitching.pitches の name・move と PitchArsenal.TYPES の向き。

const MAX_MOVE := 7
const SLOTS := {
	"カットボール": 1,
	"スライダー": 2,
	"カーブ": 3,
	"フォーク": 4,
	"スプリット": 4,
	"シンカー": 5,
	"チェンジアップ": 5,
	"シュート": 6,
	"ツーシーム": 7,
}
const COLORS := {
	"ストレート": Color("3a78c2"),
	"スライダー": Color("2b9ad4"),
	"カットボール": Color("3d8edf"),
	"カーブ": Color("5b62c9"),
	"フォーク": Color("7a56c4"),
	"スプリット": Color("6a48b6"),
	"チェンジアップ": Color("e0923a"),
	"シンカー": Color("2f9a72"),
	"シュート": Color("3aaa58"),
	"ツーシーム": Color("1f8f86"),
}
const EMPTY_FILL := Color("f4f8fb")
const EMPTY_EDGE := Color("8eacc4")
const GOLD := Color("e0a31a")
const INK := Color("1e3348")

var _items: Array = []  ## [{name, move, slot, bias, best, synthetic, dx, dy}]


func _ready() -> void:
	resized.connect(queue_redraw)


## kmh が 0 以上なら、上向きにストレートの目安（球速のランク）を足す
func set_pitches(pitches: Array, best_name: String, kmh := -1.0) -> void:
	_items.clear()
	var used := {}
	if kmh >= 0.0:
		_items.append(_make("ストレート", _straight_move(kmh), 0, 0.0, false, true))
		used[0] = true
	for x: Dictionary in pitches:
		var name := str(x.get("name", ""))
		if name.is_empty() or not SLOTS.has(name):
			continue
		var slot := int(SLOTS[name])
		var bias := 0.0
		if used.get(slot, false):
			bias = -0.42  # 同じ向きが2つ（シンカーとチェンジアップなど）は、隣へ少しずらす
		used[slot] = true
		_items.append(_make(name, clampi(int(x.get("move", 0)), 0, MAX_MOVE), slot, bias, name == best_name, false))
	var lines: PackedStringArray = []
	for e: Dictionary in _items:
		lines.append("%s %d%s" % [e["name"], int(e["move"]), " ★" if e["best"] else ""])
	tooltip_text = "捕手から見た向き（上＝ストレート、右＝スライダー側、左＝シュート側、下＝落ちる球）。塗った数＝変化量。ストレートは球速の目安。\n" + "　".join(lines)
	queue_redraw()


## テスト用。dx・dy は画面の右・下が正
func placed() -> Array:
	var out: Array = []
	for e: Dictionary in _items:
		out.append(e.duplicate())
	return out


func _make(name: String, move: int, slot: int, bias: float, best: bool, synthetic: bool) -> Dictionary:
	var dir := Vector2.from_angle(_angle(slot, bias))
	return {"name": name, "move": move, "slot": slot, "bias": bias, "best": best,
		"synthetic": synthetic, "dx": dir.x, "dy": dir.y}


func _angle(slot: int, bias: float) -> float:
	# スロット0＝上、時計回り。bias はスロット幅の割合
	return -PI * 0.5 + (float(slot) + bias) * TAU / 8.0


func _straight_move(kmh: float) -> int:
	match UiTheme.velocity_rank(kmh):
		"S":
			return 7
		"A":
			return 6
		"B":
			return 5
		"C":
			return 4
		"D":
			return 3
		"E":
			return 2
		_:
			return 1


func _draw() -> void:
	if size.x < 8.0 or size.y < 8.0:
		return
	var m := _metrics()
	var origin: Vector2 = m["origin"]
	var reach: float = m["reach"]
	var seg_len: float = m["seg_len"]
	var gap: float = m["gap"]
	var thick: float = m["thick"]
	var center_r: float = m["center_r"]
	# 持っている球だけ。各方向は7マス（塗った数＝変化量、残りは空）
	for e: Dictionary in _items:
		var dir := Vector2(float(e["dx"]), float(e["dy"]))
		var base: Color = COLORS.get(e["name"], Color("4a90c8"))
		var move := int(e["move"])
		var best: bool = e["best"]
		for i in MAX_MOVE:
			var at := _seg_center(origin, dir, center_r, seg_len, gap, i)
			if i < move:
				var fill := base.lightened(0.12 * (1.0 - float(i) / float(maxi(MAX_MOVE - 1, 1))))
				if best:
					_block(at, dir, seg_len + 2.4, thick + 2.4, GOLD, GOLD.darkened(0.2))
				_block(at, dir, seg_len, thick, fill, fill.darkened(0.28))
			else:
				_block(at, dir, seg_len, thick, EMPTY_FILL, EMPTY_EDGE)
		_label(origin, dir, reach, str(e["name"]), best, int(m["font"]))
	_baseball(origin, maxf(center_r * 0.72, 11.0))


func _metrics() -> Dictionary:
	var margin_x := 96.0
	var margin_y := 20.0
	var origin := size * 0.5
	var reach := minf(origin.x - margin_x, origin.y - margin_y)
	reach = clampf(reach, 64.0, 168.0)
	var seg_len := clampf((reach - center_pad(reach)) / 10.6, 8.0, 16.0)
	return {
		"origin": origin,
		"reach": reach,
		"seg_len": seg_len,
		"gap": seg_len * 0.42,
		"thick": seg_len * 0.72,
		"center_r": seg_len * 1.35,
		"font": clampi(roundi(reach / 11.0), 12, 15),
	}


func center_pad(reach: float) -> float:
	return clampf(reach * 0.08, 4.0, 10.0)


func _seg_center(origin: Vector2, dir: Vector2, center_r: float, seg_len: float, gap: float, i: int) -> Vector2:
	var step := seg_len + gap
	var dist := center_r + seg_len * 0.55 + float(i) * step
	return origin + dir * dist


func _block(at: Vector2, dir: Vector2, length: float, thick: float, fill: Color, edge: Color) -> void:
	var n := Vector2(-dir.y, dir.x)
	var hl := length * 0.5
	var ht := thick * 0.5
	var a := at - dir * hl
	var b := at + dir * hl
	var pts := PackedVector2Array([a + n * ht, b + n * ht, b - n * ht, a - n * ht])
	draw_colored_polygon(pts, fill)
	var line := pts.duplicate()
	line.append(pts[0])
	draw_polyline(line, edge, 1.25, true)


func _label(origin: Vector2, dir: Vector2, reach: float, text: String, best: bool, font_size: int) -> void:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var anchor := origin + dir * (reach + 2.0)
	var pos := anchor
	if dir.x >= 0.35:
		pos.y -= sz.y * 0.5
	elif dir.x <= -0.35:
		pos.x -= sz.x
		pos.y -= sz.y * 0.5
	else:
		pos.x -= sz.x * 0.5
		pos.y += 2.0 if dir.y > 0.0 else -(sz.y + 2.0)
	pos.x = clampf(pos.x, 1.0, maxf(1.0, size.x - sz.x - 1.0))
	pos.y = clampf(pos.y, 1.0, maxf(1.0, size.y - sz.y - 1.0))
	if best:
		var pad := 3.0
		var r := Rect2(pos - Vector2(pad, pad * 0.4), sz + Vector2(pad * 2.0, pad))
		var box := StyleBoxFlat.new()
		box.bg_color = Color("fff4d2")
		box.border_color = GOLD
		box.set_border_width_all(1)
		box.set_corner_radius_all(5)
		draw_style_box(box, r)
	var baseline := pos + Vector2(0.0, font.get_ascent(font_size))
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color("8a5a00") if best else INK)


func _baseball(origin: Vector2, radius: float) -> void:
	draw_circle(origin, radius, Color("fbfcfe"))
	draw_arc(origin, radius, 0.0, TAU, 28, Color("9eb0c4"), 1.6, true)
	# 縫い目は短い横線（長い縦線や弧にすると文字に見える）
	var stitch := Color("d4534a")
	for side_i in 2:
		var x: float = origin.x + (-1.0 if side_i == 0 else 1.0) * radius * 0.32
		for k in 3:
			var y: float = origin.y + (float(k) - 1.0) * radius * 0.38
			draw_line(Vector2(x - radius * 0.16, y), Vector2(x + radius * 0.16, y), stitch, 1.4, true)
