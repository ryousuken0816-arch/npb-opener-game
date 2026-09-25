class_name HubMenuButton
extends MarginContainer
## ハブ画面の大きなメニューボタン（アイコン＋太字、ボタンごとの色）。
## 選択中（フォーカス／マウスオーバー）は大きく・明るくなり、右へせり出す。

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

var key := ""

var _button := Button.new()
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat
var _tween: Tween


## glow: 選択中の影の色（球団カラー）
func setup(menu_key: String, text: String, icon: Texture2D, color: Color, glow: Color) -> void:
	key = menu_key
	_button.text = text
	_button.icon = icon
	_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_button.focus_mode = Control.FOCUS_ALL
	_button.add_theme_font_override("font", UiTheme.font(800))
	_button.add_theme_constant_override("outline_size", 10)
	_button.add_theme_constant_override("h_separation", 8)
	_button.add_theme_color_override("font_outline_color", color.darkened(0.55))
	for c in UiTheme.BUTTON_FONT_COLORS:
		_button.add_theme_color_override(c, Color.WHITE)
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_style_normal = _make_style(color, false, glow)
	_style_selected = _make_style(color.lightened(0.15), true, glow)
	add_child(_button)

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
	var current := inverse_lerp(HEIGHT, HEIGHT_SELECTED, _button.custom_minimum_size.y)
	_tween.tween_method(_apply, current, 1.0 if selected else 0.0, ANIM_SEC)
	if selected:
		focused.emit(key)


## t: 0=通常 〜 1=選択中
func _apply(t: float) -> void:
	add_theme_constant_override("margin_left", int(INDENT_SELECTED * t))
	_button.custom_minimum_size = Vector2(WIDTH + WIDTH_GROW * t, lerpf(HEIGHT, HEIGHT_SELECTED, t))
	_button.add_theme_font_size_override("font_size", int(lerpf(FONT_SIZE, FONT_SIZE_SELECTED, t)))
	_button.add_theme_constant_override("icon_max_width", int(lerpf(ICON_SIZE, ICON_SIZE_SELECTED, t)))
	var style := _style_selected if t > 0.5 else _style_normal
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		_button.add_theme_stylebox_override(state, style)


## 右上がりの平行四辺形。下辺を濃くして厚みを出す。選択中は白縁＋球団カラーの影
func _make_style(color: Color, selected: bool, glow: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.skew = Vector2(0.3, 0)
	s.set_corner_radius_all(6)
	s.content_margin_left = 18
	s.content_margin_right = 24
	s.content_margin_top = 2
	s.content_margin_bottom = 4
	s.anti_aliasing = true
	if selected:
		s.border_color = Color.WHITE
		s.set_border_width_all(4)
		s.shadow_color = Color(glow, 0.55)
		s.shadow_size = 10
		s.shadow_offset = Vector2(4, 5)
	else:
		s.border_color = color.darkened(0.3)
		s.border_width_bottom = 5
		s.shadow_color = Color(0, 0, 0, 0.22)
		s.shadow_size = 3
		s.shadow_offset = Vector2(3, 4)
	return s
