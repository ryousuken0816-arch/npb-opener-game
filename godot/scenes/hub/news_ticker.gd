class_name NewsTicker
extends CanvasLayer
## 速報の帯（ハブの下の説明の帯のすぐ上。docs/AUTORUN.md 作業25）。GameState.news_posted の速報を順に、下からせり上げて SHOW_SEC 秒出す。
## 続けて来た速報は QUEUE_LIMIT 件までためて順に出す（早送り中に多く来たら古いものは飛ばす）。入力は受けない

const SHOW_SEC := 3.2
const SLIDE_SEC := 0.18
const QUEUE_LIMIT := 4
const BAND_WIDTH := 760.0
## 画面の下端から帯の上端まで（ハブの下の帯 88px の上に置く）
const BOTTOM_GAP := 146.0

var _queue: Array[Dictionary] = []
var _band: PanelContainer
var _kind: Label
var _text: Label
var _busy := false


func _ready() -> void:
	layer = 40
	_band = PanelContainer.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_theme_stylebox_override("panel", UiTheme.gloss(Color("c62828"), 12, 3, 3, Color("ffd400")))
	_band.custom_minimum_size = Vector2(BAND_WIDTH, 0)
	add_child(_band)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.add_child(row)
	_kind = Label.new()
	UiTheme.heading(_kind, 20, Color("ffd400"), Color("7a0000"), 5)
	row.add_child(_kind)
	_text = Label.new()
	UiTheme.heading(_text, 20, Color.WHITE, Color("7a0000"), 5)
	UiTheme.fit_label(_text)
	row.add_child(_text)
	_band.visible = false


## 速報を出す（たまっていれば後ろに並ぶ）
func push(a: Dictionary) -> void:
	_queue.append(a)
	while _queue.size() > QUEUE_LIMIT:
		_queue.pop_front()
	if not _busy:
		_show_next()


## いま出ている見出し（テスト用。出ていなければ空）
func current_text() -> String:
	return _text.text if _band.visible else ""


func _show_next() -> void:
	if _queue.is_empty():
		_busy = false
		_band.visible = false
		return
	_busy = true
	var a: Dictionary = _queue.pop_front()
	_kind.text = "速報" if not a.get("mine", false) else "速報・自球団"
	_text.text = a["headline"]
	_band.visible = true
	var rect := get_viewport().get_visible_rect().size
	# スマホは画面の幅に入れて、下の操作の帯（MobileNavBar）のすぐ上に出す
	var width := minf(BAND_WIDTH, rect.x - 16.0)
	_band.custom_minimum_size.x = width
	_band.size = Vector2(width, 0)
	var x := (rect.x - width) / 2.0
	var shown_y := rect.y - BOTTOM_GAP
	if UiLayout.is_mobile:
		shown_y = rect.y - UiLayout.bottom_inset() - _band.get_combined_minimum_size().y - 8.0
	_band.position = Vector2(x, shown_y + 24)
	_band.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_band, "position", Vector2(x, shown_y), SLIDE_SEC)
	tween.parallel().tween_property(_band, "modulate:a", 1.0, SLIDE_SEC)
	tween.tween_interval(SHOW_SEC)
	tween.tween_property(_band, "modulate:a", 0.0, SLIDE_SEC)
	tween.tween_callback(_show_next)
