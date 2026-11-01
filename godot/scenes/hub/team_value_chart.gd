class_name TeamValueChart
extends Control
## 球団の位置別の得失点の棒グラフ（記録室の「位置別の戦力」、作業34）。
## 横に TeamValue.COLUMNS（先発・救援・捕手〜右翼・DH）、縦にリーグ平均＝0 の得失点。プラスは球団カラー、マイナスは青。
## 棒の上（下）に値、目盛りは10点ごと（値が大きければ20点ごと）

const MINUS_COLOR := Color("4f7cc9")
const GRID_COLOR := Color(0, 0, 0, 0.10)
const AXIS_COLOR := Color(0, 0, 0, 0.55)
const LEFT := 56.0
const BOTTOM := 34.0
const TOP := 26.0

var _values := {}  ## 位置 → 点
var _color := Color("e53935")


## values は TeamValue の1球団分（位置 → {total, ...}）
func set_data(values: Dictionary, plus_color: Color) -> void:
	_values = {}
	for col: String in TeamValue.COLUMNS:
		_values[col] = float(values.get(col, {}).get("total", 0.0))
	_color = plus_color
	queue_redraw()


func value_of(col: String) -> float:
	return float(_values.get(col, 0.0))


func _draw() -> void:
	var font := UiTheme.font(800)
	var w := size.x - LEFT - 8.0
	var h := size.y - TOP - BOTTOM
	if w <= 0.0 or h <= 0.0:
		return
	var top_v := 10.0
	for col: String in _values:
		top_v = maxf(top_v, absf(float(_values[col])))
	var step := 10.0 if top_v <= 40.0 else 20.0
	top_v = ceilf(top_v / step) * step
	var y_of := func(v: float) -> float: return TOP + h * 0.5 - v / top_v * h * 0.5
	# 目盛り
	var v := -top_v
	while v <= top_v + 0.01:
		var y: float = y_of.call(v)
		draw_line(Vector2(LEFT, y), Vector2(LEFT + w, y), AXIS_COLOR if is_zero_approx(v) else GRID_COLOR,
			2.0 if is_zero_approx(v) else 1.0)
		draw_string(font, Vector2(0, y + 5), "%+d" % int(v) if not is_zero_approx(v) else "0",
			HORIZONTAL_ALIGNMENT_RIGHT, LEFT - 8.0, 13, UiTheme.TEXT_SUB)
		v += step
	# 棒
	var n := TeamValue.COLUMNS.size()
	var slot := w / n
	for i in n:
		var col: String = TeamValue.COLUMNS[i]
		var value := float(_values.get(col, 0.0))
		var x := LEFT + slot * i + slot * 0.18
		var bw := slot * 0.64
		var y0: float = y_of.call(0.0)
		var y1: float = y_of.call(value)
		var rect := Rect2(x, minf(y0, y1), bw, absf(y1 - y0))
		draw_rect(rect, _color if value >= 0.0 else MINUS_COLOR)
		var text := "%+.0f" % value if absf(value) >= 0.5 else "0"
		var ty := (rect.position.y - 6.0) if value >= 0.0 else (rect.end.y + 17.0)
		draw_string(font, Vector2(LEFT + slot * i, ty), text, HORIZONTAL_ALIGNMENT_CENTER, slot, 15, UiTheme.TEXT)
		draw_string(font, Vector2(LEFT + slot * i, size.y - 10.0), TeamValue.SHORT[col], HORIZONTAL_ALIGNMENT_CENTER,
			slot, 15, UiTheme.TEXT)
