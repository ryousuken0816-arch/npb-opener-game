class_name PitchChart
extends Control
## 投手の持ち球の目盛り（docs/AUTORUN.md 作業79。ユーザー決定 2026-11-09 の表示）。差し替えやすいように1つのシーン（pitch_chart.tscn）にしてある。
## 球種名を真ん中に置き、横に曲がる球は曲がる側（左＝シュート側・右＝スライダー側）へ、落ちる球は下へ、MAX_MOVE 個の目盛りが伸びる。
## 埋まった数＝変化量（1〜7）。決め球は濃い色と★。データは PitchArsenal（pitching.pitches の name・move、向きは PitchArsenal.TYPES の dir）

const MAX_MOVE := 7
const CELL := 14.0
const CELL_GAP := 2.0
const NAME_W := 132.0
const ROW_H := 22.0
const HEAD_H := 18.0
## 落ちる球の列：幅・目盛りの高さ
const DOWN_W := 140.0
const DOWN_CELL_H := 9.0
const FONT_SIZE := 15
const HEAD_SIZE := 12
const FILL := Color("5d9be3")
const FILL_BEST := Color("1c4c94")
const EMPTY := Color("dde6f0")
const INK := Color("23364d")
const SUB := Color("6b7d90")

var _side: Array = []  ## [{name, move, dir, best}]（横の球）
var _down: Array = []  ## 落ちる球


func set_pitches(pitches: Array, best_name: String) -> void:
	_side.clear()
	_down.clear()
	for x: Dictionary in pitches:
		var dir := str(PitchArsenal.TYPES.get(str(x["name"]), {}).get("dir", "右"))
		var e := {"name": str(x["name"]), "move": clampi(int(x["move"]), 0, MAX_MOVE), "dir": dir, "best": str(x["name"]) == best_name}
		(_down if dir == "下" else _side).append(e)
	custom_minimum_size = Vector2(_width(), _height())
	tooltip_text = "持ち球の変化量（1〜%d）。★は決め球" % MAX_MOVE
	queue_redraw()


func _width() -> float:
	return NAME_W + 2.0 * (MAX_MOVE * (CELL + CELL_GAP) + 4.0)


func _height() -> float:
	var h := HEAD_H + _side.size() * ROW_H
	if not _down.is_empty():
		h += 4.0 + ROW_H + MAX_MOVE * (DOWN_CELL_H + CELL_GAP)
	return h


func _draw() -> void:
	var font := get_theme_default_font()
	var w := maxf(size.x, _width())
	var cx := w / 2.0
	var half := NAME_W / 2.0
	# 見出し：向き
	_text(font, Vector2(cx - half - 4.0, 0.0), "← シュート側", HEAD_SIZE, SUB, HORIZONTAL_ALIGNMENT_RIGHT, MAX_MOVE * (CELL + CELL_GAP))
	_text(font, Vector2(cx + half + 4.0, 0.0), "スライダー側 →", HEAD_SIZE, SUB, HORIZONTAL_ALIGNMENT_LEFT, MAX_MOVE * (CELL + CELL_GAP))
	var y := HEAD_H
	for e: Dictionary in _side:
		_name_box(font, Rect2(cx - half, y, NAME_W, ROW_H - 3.0), e)
		var dsign := -1.0 if e["dir"] == "左" else 1.0
		for i in MAX_MOVE:
			var x0 := cx + dsign * (half + 4.0 + i * (CELL + CELL_GAP))
			var r := Rect2(x0 if dsign > 0.0 else x0 - CELL, y + (ROW_H - 3.0 - CELL) / 2.0, CELL, CELL)
			draw_rect(r, _cell_color(e, i))
		y += ROW_H
	if _down.is_empty():
		return
	y += 4.0
	var total := _down.size() * DOWN_W
	var left := cx - total / 2.0
	for j in _down.size():
		var e: Dictionary = _down[j]
		var colx := left + j * DOWN_W
		_name_box(font, Rect2(colx + 4.0, y, DOWN_W - 8.0, ROW_H - 3.0), e)
		var bar_w := DOWN_W - 76.0
		for i in MAX_MOVE:
			var r := Rect2(colx + (DOWN_W - bar_w) / 2.0, y + ROW_H + i * (DOWN_CELL_H + CELL_GAP), bar_w, DOWN_CELL_H)
			draw_rect(r, _cell_color(e, i))
	_text(font, Vector2(left - 70.0, y + ROW_H), "落ちる球 ↓", HEAD_SIZE, SUB, HORIZONTAL_ALIGNMENT_RIGHT, 64.0)


func _cell_color(e: Dictionary, i: int) -> Color:
	if i < int(e["move"]):
		return FILL_BEST if bool(e["best"]) else FILL
	return EMPTY


func _name_box(font: Font, r: Rect2, e: Dictionary) -> void:
	var best := bool(e["best"])
	var box := StyleBoxFlat.new()
	box.bg_color = Color("fff4d6") if best else Color("f1f4f7")
	box.border_color = Color("d9a526") if best else Color("c5ccd4")
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	draw_style_box(box, r)
	var label := ("★" if best else "") + str(e["name"]) + " " + str(e["move"])
	_text(font, Vector2(r.position.x, r.position.y + 1.0), label, FONT_SIZE, INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


func _text(font: Font, pos: Vector2, text: String, fsize: int, color: Color, align: HorizontalAlignment, width: float) -> void:
	var p := pos
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	draw_string(font, p + Vector2(0.0, font.get_ascent(fsize)), text, align, width, fsize, color)
