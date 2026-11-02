class_name PadGuide
extends Control
## 画面右上の操作ガイド（参考画像の右上のボタン表示）。Xbox 式のボタン記号：Ⓐ決定 Ⓑ戻る LB/RB切替。
## items は [ボタン, 説明] の配列。ボタンは "A" "B" "X" "Y"（丸）か "LB/RB" など（角丸の札）。

const BUTTON_COLORS := {
	"A": Color("3fa535"), "B": Color("d9322b"), "X": Color("2f6fd6"), "Y": Color("e0a800"),
}
const SHOULDER_COLOR := Color("4a5058")
const FONT_SIZE := 15
const ICON := 20.0
const GAP := 12.0
const PAD := 10.0

var items: Array = [["A", "決定"], ["B", "戻る"], ["LB/RB", "切替"]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# スマホ表示ではコントローラーのボタンの案内は出さない（大きさも0にして場所を取らない）
	UiLayout.layout_changed.connect(func(_p: bool, _m: bool) -> void:
		_update_size()
		queue_redraw())
	_update_size()


func set_items(new_items: Array) -> void:
	items = new_items
	_update_size()
	queue_redraw()


func _update_size() -> void:
	custom_minimum_size = Vector2.ZERO if UiLayout.is_mobile else Vector2(_content_width() + PAD * 2, ICON + 8)
	size = custom_minimum_size


func _content_width() -> float:
	var font := UiTheme.font(800)
	var w := 0.0
	for item: Array in items:
		w += _icon_width(item[0]) + 4
		w += font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + GAP
	return w - GAP


func _icon_width(button: String) -> float:
	if BUTTON_COLORS.has(button):
		return ICON
	var font := UiTheme.font(800)
	return font.get_string_size(button, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 3).x + 12


func _draw() -> void:
	if UiLayout.is_mobile:
		return
	var font := UiTheme.font(800)
	var pill := UiTheme.box(Color(1, 1, 1, 0.88), int(size.y / 2), Color(0, 0, 0, 0.12), 1)
	pill.shadow_color = Color(0, 0, 0, 0.15)
	pill.shadow_size = 3
	pill.shadow_offset = Vector2(0, 2)
	draw_style_box(pill, Rect2(Vector2.ZERO, size))
	var x := PAD
	var cy := size.y / 2
	for item: Array in items:
		var button: String = item[0]
		var iw := _icon_width(button)
		if BUTTON_COLORS.has(button):
			var c: Color = BUTTON_COLORS[button]
			var center := Vector2(x + ICON / 2, cy)
			draw_circle(center + Vector2(0, 1), ICON / 2, c.darkened(0.4))
			draw_circle(center, ICON / 2, c)
			draw_circle(center - Vector2(0, ICON * 0.18), ICON * 0.3, Color(1, 1, 1, 0.25))
			_centered(font, button, center, FONT_SIZE - 2, Color.WHITE)
		else:
			var r := Rect2(x, cy - ICON / 2 + 1, iw, ICON - 2)
			var s := UiTheme.box(SHOULDER_COLOR, 5)
			draw_style_box(s, r)
			_centered(font, button, r.get_center(), FONT_SIZE - 3, Color.WHITE)
		x += iw + 4
		var baseline := cy + (font.get_ascent(FONT_SIZE) - font.get_descent(FONT_SIZE)) / 2
		draw_string(font, Vector2(x, baseline), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			UiTheme.TEXT)
		x += font.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + GAP


func _centered(font: Font, text: String, center: Vector2, fs: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var baseline := center.y + (font.get_ascent(fs) - font.get_descent(fs)) / 2
	draw_string(font, Vector2(center.x - w / 2, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		color)
