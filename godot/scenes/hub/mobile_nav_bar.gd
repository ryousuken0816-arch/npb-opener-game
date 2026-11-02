class_name MobileNavBar
extends CanvasLayer
## スマホ表示のときだけ画面の下に出す操作の帯（ハブが持つ）。大きな「戻る」と、よく使うボタン（日程表・采配・可変ボタン）。
## 選手詳細（層50）より上に出す。縦向きはボタンの上に1行の案内（パソコンの下の帯の説明と同じ文言）、横向きは案内をボタンの左に。
## 高さは UiLayout.bottom_inset()（サブ画面・選手詳細はこの分だけ下を空ける）。

## ボタンを押した（"back" / "schedule" / "tactics" / "advance" / "mode"）
signal chosen(key: String)

const LAYER := 60

var _panel := PanelContainer.new()
var _box := BoxContainer.new()
var _message := Label.new()
var _buttons := HBoxContainer.new()
var _back: Button
var _advance: Button
var _mode: Button
## 案内の写し元（ハブの下の帯の説明のラベル）と、「戻る」を押せるか・可変ボタンの文言を返す関数
var _source: Label
var _can_back: Callable
var _advance_text: Callable


func setup(palette: UiTheme.Palette, source: Label, can_back: Callable, advance_text: Callable) -> void:
	layer = LAYER
	_source = source
	_can_back = can_back
	_advance_text = advance_text
	var style := UiTheme.card(palette.main, 0, 0, 0.97)
	style.border_width_top = 4
	style.shadow_offset = Vector2(0, -2)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_meta("touch_keep", true)
	add_child(_panel)
	_box.add_theme_constant_override("separation", 2)
	_panel.add_child(_box)
	_message.add_theme_font_override("font", UiTheme.font(700))
	_message.add_theme_color_override("font_color", UiTheme.TEXT)
	UiTheme.fit_label(_message)
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_box.add_child(_message)
	_buttons.add_theme_constant_override("separation", 6)
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_child(_buttons)
	_back = _button("← 戻る", Color("5f6670"), "back")
	_button("日程表", Color("e84393"), "schedule")
	_button("采配", Color("f57c00"), "tactics")
	_advance = _button("▶", Color("e53935"), "advance")
	_advance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode = _button("PC表示", Color("455a64"), "mode")


func _ready() -> void:
	get_viewport().size_changed.connect(_place)
	UiLayout.layout_changed.connect(func(_p: bool, _m: bool) -> void: _place())
	_place()


func _button(text: String, color: Color, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiTheme.font(800))
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiTheme.style_button(b, color, Color.WHITE, 10, 3)
	b.pressed.connect(func() -> void: chosen.emit(key))
	_buttons.add_child(b)
	return b


func _place() -> void:
	visible = UiLayout.is_mobile
	if not visible:
		return
	var view := _panel.get_viewport_rect().size
	var portrait := UiLayout.is_portrait
	var t := UiLayout.touch_units()
	_box.vertical = portrait
	_message.visible = true
	_message.custom_minimum_size = Vector2(0, UiLayout.NAV_MESSAGE_HEIGHT if portrait else t)
	_message.add_theme_font_size_override("font_size", 15 if portrait else 18)
	_message.autowrap_mode = TextServer.AUTOWRAP_OFF if portrait else TextServer.AUTOWRAP_WORD_SMART
	_message.max_lines_visible = 1 if portrait else 2
	_message.clip_text = portrait
	_buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL if portrait else Control.SIZE_SHRINK_END
	var font := 17 if portrait else 22
	for b: Button in _buttons.get_children():
		b.add_theme_font_size_override("font_size", font)
		b.custom_minimum_size = Vector2(t * (1.5 if portrait else 2.2), t)
	_buttons.get_child(2).custom_minimum_size.x = t * (1.25 if portrait else 2.2)  # 采配（2文字）
	_advance.custom_minimum_size.x = t * (1.6 if portrait else 3.4)
	_mode.custom_minimum_size.x = t * 0.95 if portrait else t * 1.6
	_mode.add_theme_font_size_override("font_size", 13 if portrait else 18)
	_mode.visible = UiLayout.on_phone()
	var h := UiLayout.bottom_inset()
	_panel.position = Vector2(0, view.y - h)
	_panel.size = Vector2(view.x, h)
	var style: StyleBox = _panel.get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		(style as StyleBoxFlat).content_margin_bottom = 4 + UiLayout.safe_area_bottom


func _process(_delta: float) -> void:
	if not visible:
		return
	if _source != null and _message.text != _source.text:
		_message.text = _source.text
	_back.disabled = not bool(_can_back.call())
	var adv := "▶ " + str(_advance_text.call())
	if _advance.text != adv:
		_advance.text = adv


## テスト用：ボタンを押す
func press(key: String) -> void:
	chosen.emit(key)
