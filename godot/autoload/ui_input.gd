extends Node
## コントローラー操作（docs/references/README.md「コントローラー操作」）。オートロード `UiInput`。
##
## - 十字キー／左スティック＝フォーカス移動（Godot 標準の ui_up/down/left/right）
## - Ⓐ＝決定（ui_accept）、Ⓑ＝戻る（ui_cancel、Esc と同じ）。PS なら ○×
## - LB/RB（L1/R1）＝タブ切り替え（ui_tab_prev / ui_tab_next。キーボードは Q / E・PageUp / PageDown）
## - Switch 配置向けに決定と戻るのボタンを入れ替えられる（SWAP_CONFIRM_CANCEL。システム設定ができたらそちらへ）
## - マウスを乗せたときだけ出るツールチップを、十字キー・キーボードでフォーカスしたときにも出す
## - どこにもフォーカスがないときに十字キーを押したら、画面の最初のボタンにフォーカスする
## - 十字キー・左スティックを倒し続けたら、キーボードの長押しと同じく連続でフォーカスを動かす
##   （最初の1回は Godot 標準の ui_* の動き。REPEAT_DELAY 秒後から REPEAT_INTERVAL 秒ごとに
##   InputEventAction を viewport に送る。Input の押下状態は変えない）

## true にすると Ⓐ（下のボタン）が戻る、Ⓑ（右のボタン）が決定になる（Switch の配置）
const SWAP_CONFIRM_CANCEL := false
const TAB_PREV := "ui_tab_prev"
const TAB_NEXT := "ui_tab_next"
const TOOLTIP_DELAY := 0.35
## 押しっぱなしの連続移動：最初の待ち時間と、その後の間隔（秒）
const REPEAT_DELAY := 0.35
const REPEAT_INTERVAL := 0.08
## 左スティックをこれより小さく倒しただけでは動かない（ui_* の deadzone にも使う）
const STICK_DEADZONE := 0.5
const DIRECTIONS := ["ui_up", "ui_down", "ui_left", "ui_right"]
const DPAD_DIRECTION := {
	JOY_BUTTON_DPAD_UP: "ui_up", JOY_BUTTON_DPAD_DOWN: "ui_down",
	JOY_BUTTON_DPAD_LEFT: "ui_left", JOY_BUTTON_DPAD_RIGHT: "ui_right",
}

## 最後の操作がマウスだったか（ツールチップをどちらの仕組みで出すかに使う）
var using_mouse := true

var _tip_layer := CanvasLayer.new()
var _tip_panel := PanelContainer.new()
var _tip_label := Label.new()
var _tip_timer := Timer.new()
var _tip_target: Control

## 押しっぱなしの十字キー（"デバイス:ボタン" → 方向）と左スティックの傾き（デバイス → Vector2）
var _dpad_held := {}
var _stick := {}
## 連続移動中の方向（無ければ ""）と、次に送る時刻（ミリ秒）
var _repeat_dir := ""
var _repeat_next_msec := 0


func _ready() -> void:
	_setup_actions()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip_layer.layer = 100
	add_child(_tip_layer)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = Color("ffb300")
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 4
	style.set_content_margin_all(8)
	_tip_panel.add_theme_stylebox_override("panel", style)
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_panel.visible = false
	_tip_label.add_theme_color_override("font_color", Color("2b2f36"))
	_tip_label.add_theme_font_size_override("font_size", 16)
	_tip_label.add_theme_font_override("font", UiTheme.font(700))
	_tip_panel.add_child(_tip_label)
	_tip_layer.add_child(_tip_panel)
	_tip_timer.one_shot = true
	_tip_timer.wait_time = TOOLTIP_DELAY
	_tip_timer.timeout.connect(_show_tip)
	add_child(_tip_timer)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void:
		_dpad_held.clear()
		_stick.clear())


func _setup_actions() -> void:
	_add_action(TAB_PREV, [KEY_Q, KEY_PAGEUP], [JOY_BUTTON_LEFT_SHOULDER])
	_add_action(TAB_NEXT, [KEY_E, KEY_PAGEDOWN], [JOY_BUTTON_RIGHT_SHOULDER])
	_set_joy_button("ui_accept", JOY_BUTTON_B if SWAP_CONFIRM_CANCEL else JOY_BUTTON_A)
	_set_joy_button("ui_cancel", JOY_BUTTON_A if SWAP_CONFIRM_CANCEL else JOY_BUTTON_B)
	for dir: String in DIRECTIONS:
		InputMap.action_set_deadzone(dir, STICK_DEADZONE)


func _add_action(action: String, keys: Array, buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key: Key in keys:
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)
	for button: JoyButton in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		InputMap.action_add_event(action, e)


## action に割り当てるコントローラーのボタンを1つにする（キーボードの割り当てはそのまま）
func _set_joy_button(action: String, button: JoyButton) -> void:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton:
			InputMap.action_erase_event(action, e)
	var joy := InputEventJoypadButton.new()
	joy.button_index = button
	InputMap.action_add_event(action, joy)


func _input(event: InputEvent) -> void:
	_track_held(event)
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if not using_mouse:
			using_mouse = true
			_hide_tip()
		return
	if event is InputEventKey or event is InputEventJoypadButton \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		using_mouse = false
		# どこにもフォーカスがないときは、十字キーで画面の最初のボタンを選ぶ
		if get_viewport().gui_get_focus_owner() == null:
			for dir in ["ui_up", "ui_down", "ui_left", "ui_right"]:
				if event.is_action_pressed(dir):
					if focus_first(get_tree().current_scene):
						get_viewport().set_input_as_handled()
					return


# --- 押しっぱなしの連続移動 -------------------------------------------------------------

func _track_held(event: InputEvent) -> void:
	if event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if DPAD_DIRECTION.has(jb.button_index):
			var key := "%d:%d" % [jb.device, jb.button_index]
			if jb.pressed:
				_dpad_held[key] = DPAD_DIRECTION[jb.button_index]
			else:
				_dpad_held.erase(key)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if jm.axis == JOY_AXIS_LEFT_X or jm.axis == JOY_AXIS_LEFT_Y:
			var v: Vector2 = _stick.get(jm.device, Vector2.ZERO)
			if jm.axis == JOY_AXIS_LEFT_X:
				v.x = jm.axis_value
			else:
				v.y = jm.axis_value
			_stick[jm.device] = v


## いま押しっぱなしの方向（十字キー優先。スティックは大きく倒しているほうの軸）。無ければ ""
func _held_direction() -> String:
	for dir: String in _dpad_held.values():
		return dir
	for v: Vector2 in _stick.values():
		if absf(v.x) < STICK_DEADZONE and absf(v.y) < STICK_DEADZONE:
			continue
		if absf(v.y) >= absf(v.x):
			return "ui_down" if v.y > 0.0 else "ui_up"
		return "ui_right" if v.x > 0.0 else "ui_left"
	return ""


func _process(_delta: float) -> void:
	var dir := _held_direction()
	var now := Time.get_ticks_msec()
	if dir != _repeat_dir:
		_repeat_dir = dir
		_repeat_next_msec = now + int(REPEAT_DELAY * 1000.0)
		return
	if dir.is_empty() or now < _repeat_next_msec:
		return
	_repeat_next_msec = now + int(REPEAT_INTERVAL * 1000.0)
	var e := InputEventAction.new()
	e.action = dir
	e.pressed = true
	get_viewport().push_input(e)


# --- フォーカスの補助 -----------------------------------------------------------------

## c にフォーカスする（押せなければ何もしない）。押せるようになったばかりのボタンにも使える
func grab(c: Control) -> bool:
	if c is BaseButton:
		UiFx.sync_focus_mode(c)
	if c == null or not c.is_visible_in_tree() or c.focus_mode == Control.FOCUS_NONE:
		return false
	c.grab_focus()
	return true


## root 以下で最初の（木の順で）フォーカスできる見えている Control にフォーカスする
func focus_first(root: Node) -> bool:
	var target := first_focusable(root)
	if target != null:
		target.grab_focus()
		return true
	return false


func first_focusable(root: Node) -> Control:
	var list := focusables(root)
	return list[0] if not list.is_empty() else null


## root 以下のフォーカスできる見えている Control（木の順）
func focusables(root: Node) -> Array[Control]:
	var result: Array[Control] = []
	_collect(root, result)
	return result


func _collect(node: Node, result: Array[Control]) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible:
		return
	if node is Control:
		var c := node as Control
		if c is BaseButton:
			UiFx.sync_focus_mode(c)
		if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
			result.append(c)
	for child in node.get_children():
		_collect(child, result)


## いまフォーカスしている項目が root 以下の何番目か（root 以下になければ -1）。
## 作り直す画面で、作り直したあとも同じ位置にフォーカスを戻すのに使う
func focus_index(root: Node) -> int:
	var owner_control := get_viewport().gui_get_focus_owner()
	if owner_control == null or not root.is_ancestor_of(owner_control):
		return -1
	return focusables(root).find(owner_control)


## root 以下の index 番目（範囲外なら最後）にフォーカスする
func focus_nth(root: Node, index: int) -> void:
	var list := focusables(root)
	if list.is_empty() or index < 0:
		return
	list[mini(index, list.size() - 1)].grab_focus()


# --- フォーカスしたときのツールチップ ---------------------------------------------------

func _on_focus_changed(control: Control) -> void:
	_hide_tip()
	_tip_target = control
	if using_mouse or control == null or control.tooltip_text.is_empty():
		return
	_tip_timer.start()


func _show_tip() -> void:
	var c := _tip_target
	if not is_instance_valid(c) or not c.is_visible_in_tree() or not c.has_focus() or using_mouse:
		return
	_tip_label.text = c.tooltip_text
	_tip_panel.reset_size()
	_tip_panel.visible = true
	var rect := c.get_global_rect()
	var view := get_viewport().get_visible_rect().size
	var tip_size := _tip_panel.get_combined_minimum_size()
	var pos := Vector2(rect.position.x + 12, rect.end.y + 6)
	if pos.y + tip_size.y > view.y:
		pos.y = rect.position.y - tip_size.y - 6
	pos.x = clampf(pos.x, 4, view.x - tip_size.x - 4)
	_tip_panel.position = pos


## 出ているツールチップを消す（フォーカスを外しただけでは消えないので、画面を重ねるときに呼ぶ）
func hide_tip() -> void:
	_hide_tip()


func _hide_tip() -> void:
	_tip_timer.stop()
	_tip_panel.visible = false
