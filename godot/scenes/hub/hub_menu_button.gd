class_name HubMenuButton
extends MarginContainer
## ハブ画面の大きなメニューボタン（アイコン＋太字、ボタンごとの色）。立体（GlossBox：グラデーション＋ツヤ＋厚み）。
## 選択中（フォーカス／マウスオーバー）は大きく・明るくなり、右へせり出し、黄色い縁と光がゆっくり明滅する。
## 押すと沈む。十字キー（上下）で移動、Ⓐ で決定。

signal focused(key: String)
signal chosen(key: String)

const WIDTH := 270.0
const HEIGHT := 60.0
const HEIGHT_SELECTED := 78.0
const WIDTH_GROW := 30.0
const INDENT_SELECTED := 34.0
const FONT_SIZE := 28
const FONT_SIZE_SELECTED := 36
const ICON_SIZE := 46
const ICON_SIZE_SELECTED := 62
const ANIM_SEC := 0.12
const SELECTED_BORDER := Color("ffd400")
## 選択中の光の明滅の周期（秒）
const GLOW_SEC := 1.4

var key := ""
## 中のボタンの無効化（hub.gd が「進める」の間だけ押せなくする）
var disabled: bool:
	get:
		return _button.disabled
	set(value):
		_button.disabled = value

var _button := Button.new()
var _style_normal: GlossBox
var _style_selected: GlossBox
var _tween: Tween
var _glow := 0.0


## glow: 選択中の影の色（球団カラー）
func setup(menu_key: String, text: String, icon: Texture2D, color: Color, glow: Color) -> void:
	key = menu_key
	_button.text = text
	_button.icon = icon
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.focus_mode = Control.FOCUS_ALL
	_button.add_theme_font_override("font", UiTheme.font(800))
	_button.add_theme_constant_override("outline_size", 8)
	_button.add_theme_constant_override("h_separation", 12)
	_button.add_theme_color_override("font_outline_color", color.darkened(0.55))
	for c in UiTheme.BUTTON_FONT_COLORS:
		_button.add_theme_color_override(c, Color.WHITE)
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.set_meta("no_fx", true)
	_style_normal = _make_style(color, false, glow)
	_style_selected = _make_style(color.lightened(0.12), true, glow)
	add_child(_button)
	set_process(false)

	_button.mouse_entered.connect(_button.grab_focus)
	_button.focus_entered.connect(_on_focus_changed.bind(true))
	_button.focus_exited.connect(_on_focus_changed.bind(false))
	_button.pressed.connect(func() -> void: chosen.emit(key))
	_apply(0.0)


func set_text(text: String) -> void:
	_button.text = text


func grab_button_focus() -> void:
	_button.grab_focus()


func _on_focus_changed(selected: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var current := inverse_lerp(_height(), _height() + HEIGHT_SELECTED - HEIGHT, _button.custom_minimum_size.y)
	_tween.tween_method(_apply, current, 1.0 if selected else 0.0, ANIM_SEC)
	set_process(selected)
	if selected:
		_glow = 0.0
		focused.emit(key)


## 選択中の光（影の色の濃さと広がり）をゆっくり明滅させる
func _process(delta: float) -> void:
	_glow = fmod(_glow + delta, GLOW_SEC)
	var wave := 0.5 + 0.5 * cos(_glow / GLOW_SEC * TAU)
	_style_selected.shadow_color = Color(SELECTED_BORDER, 0.45 + 0.4 * wave)
	_style_selected.shadow_size = int(8 + 7 * wave)
	_button.queue_redraw()


## t: 0=通常 〜 1=選択中
func _apply(t: float) -> void:
	add_theme_constant_override("margin_left", int(INDENT_SELECTED * t))
	_button.custom_minimum_size = Vector2(WIDTH + WIDTH_GROW * t, lerpf(_height(), _height() + HEIGHT_SELECTED - HEIGHT, t))
	_button.add_theme_font_size_override("font_size", int(lerpf(FONT_SIZE, FONT_SIZE_SELECTED, t)))
	_button.add_theme_constant_override("icon_max_width", int(lerpf(ICON_SIZE, ICON_SIZE_SELECTED, t)))
	var style := _style_selected if t > 0.5 else _style_normal
	for state in ["normal", "hover"]:
		_button.add_theme_stylebox_override(state, style)
	var sunk := style.pressed_copy()
	_button.add_theme_stylebox_override("pressed", sunk)
	_button.add_theme_stylebox_override("hover_pressed", sunk)


## 右上がりの平行四辺形。縦グラデーション＋ツヤ、下辺に厚み。選択中は黄色い縁＋光（明滅は _process）
## 選んでいないときの高さ（スマホは指で押しやすい大きさ以上）
func _height() -> float:
	return maxf(HEIGHT, UiLayout.touch_units())


func _make_style(color: Color, selected: bool, glow: Color) -> GlossBox:
	var s := UiTheme.gloss(color, 7, 3, 5)
	s.skew = Vector2(0.3, 0)
	s.gloss = 0.5
	s.gradient = 0.2
	s.content_margin_left = 20
	s.content_margin_right = 24
	s.content_margin_top = 2
	s.content_margin_bottom = 4 + s.depth
	if selected:
		s.border_color = SELECTED_BORDER
		s.set_border_width_all(5)
		s.border_width_bottom = 3
		s.shadow_color = Color(SELECTED_BORDER, 0.6)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 0)
	else:
		s.border_color = color.darkened(0.35)
		s.shadow_color = Color(glow.darkened(0.5), 0.3)
		s.shadow_size = 3
		s.shadow_offset = Vector2(3, 4)
	return s
