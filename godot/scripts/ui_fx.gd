class_name UiFx
extends RefCounted
## 画面の動き（docs/references/README.md「UI全体の質感アップ」4）。テンポ重視で 0.1〜0.2 秒の短い演出だけ。
##
## - install(root)：root 以下のボタン（あとから追加されるものも）に、選択中（フォーカス）で少し拡大して
##   ゆっくり明滅・押すと沈む、を付ける。トグルで選ばれているボタンも明滅する。
##   マウスを乗せるとそのボタンにフォーカスが移るので、マウスとコントローラー（十字キー）の選択位置は常に1つ。
##   メタ "no_fx" を付けたボタンは対象外
## - slide_in / fade_in：画面の切り替え
## - bump：数字が変わったときに軽く弾ませる

const HOVER_SCALE := 1.045
const PRESS_SCALE := 0.96
const HOVER_SEC := 0.1
const PRESS_SEC := 0.06
const SWITCH_SEC := 0.16
const BUMP_SEC := 0.18
## 明滅の片道の秒数（ゆっくり）と明るさ
const PULSE_SEC := 0.7
const PULSE_BRIGHT := Color(1.14, 1.14, 1.14)


static func install(root: Node) -> void:
	var tree := root.get_tree()
	var on_added := func(node: Node) -> void:
		if node is BaseButton and root.is_ancestor_of(node):
			attach_button(node)
	tree.node_added.connect(on_added)
	root.tree_exiting.connect(func() -> void:
		if tree.node_added.is_connected(on_added):
			tree.node_added.disconnect(on_added))
	_attach_all(root)


static func _attach_all(node: Node) -> void:
	if node is BaseButton:
		attach_button(node)
	for child in node.get_children():
		_attach_all(child)


static func attach_button(b: BaseButton) -> void:
	if b.has_meta("no_fx") or b.has_meta("_fx"):
		return
	b.set_meta("_fx", true)
	b.mouse_entered.connect(func() -> void:
		if b.disabled:
			return
		if b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
		else:
			_scale_to(b, HOVER_SCALE, HOVER_SEC))
	b.mouse_exited.connect(func() -> void:
		if not b.has_focus():
			_scale_to(b, 1.0, HOVER_SEC))
	b.focus_entered.connect(func() -> void:
		if not b.disabled:
			_scale_to(b, HOVER_SCALE, HOVER_SEC)
		_update_pulse(b))
	b.focus_exited.connect(func() -> void:
		_scale_to(b, 1.0, HOVER_SEC)
		_update_pulse(b))
	b.button_down.connect(func() -> void: _scale_to(b, PRESS_SCALE, PRESS_SEC))
	b.button_up.connect(func() -> void:
		_scale_to(b, HOVER_SCALE if _is_lit(b) else 1.0, HOVER_SEC))
	# set_pressed_no_signal・disabled の切り替えにも追従するよう、描き直しのたびに確かめる。
	# 押せないボタンには十字キーのフォーカスが止まらないようにする（押せるようになったら戻す）
	b.set_meta("_focus_mode", b.focus_mode)
	b.draw.connect(func() -> void:
		_update_pulse(b)
		sync_focus_mode(b))
	_update_pulse.call_deferred(b)


## 押せないボタンはフォーカスできなくする（押せるようになったら元に戻す）。
## 描き直しを待たずに今の状態に合わせたいとき（フォーカスを移す直前など）にも呼ぶ
static func sync_focus_mode(b: BaseButton) -> void:
	if not b.has_meta("_focus_mode"):
		return
	var want: int = Control.FOCUS_NONE if b.disabled else int(b.get_meta("_focus_mode"))
	if b.focus_mode != want:
		b.focus_mode = want as Control.FocusMode


static func _is_lit(b: BaseButton) -> bool:
	return not b.disabled and (b.has_focus() or b.is_hovered())


## 選択中（フォーカス）またはトグルが入っている間だけゆっくり明滅させる
static func _update_pulse(b: BaseButton) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	var on := not b.disabled and (b.has_focus() or (b.toggle_mode and b.button_pressed))
	var running: Tween = b.get_meta("_pulse") if b.has_meta("_pulse") else null
	if on and (running == null or not running.is_valid()):
		pulse(b)
	elif not on and running != null and running.is_valid():
		running.kill()
		b.remove_meta("_pulse")
		b.self_modulate = Color.WHITE


## ゆっくり明滅（止めるときは戻り値の Tween を kill して self_modulate を白に戻す）
static func pulse(c: CanvasItem) -> Tween:
	var tw := c.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(c, "self_modulate", PULSE_BRIGHT, PULSE_SEC)
	tw.tween_property(c, "self_modulate", Color.WHITE, PULSE_SEC)
	c.set_meta("_pulse", tw)
	return tw


static func _scale_to(c: Control, target: float, sec: float) -> void:
	if not c.is_inside_tree():
		return
	c.pivot_offset = c.size * 0.5
	var old: Tween = c.get_meta("_scale_tween") if c.has_meta("_scale_tween") else null
	if old != null and old.is_valid():
		old.kill()
	var tw := c.create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(target, target), sec)
	c.set_meta("_scale_tween", tw)


## 画面の切り替え：少し横からすべり込みながらフェードイン（アンカー配置のパネル向け）。
## position を動かす＝アンカーからの余白（offset_*）が動くので、途中で配置を変えるときは先に stop_slide() で止める
static func slide_in(c: Control, from := Vector2(28, 0)) -> void:
	stop_slide(c)
	var end := c.position
	c.set_meta("_slide_end", end)
	c.position = end + from
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position", end, SWITCH_SEC)
	tw.tween_property(c, "modulate:a", 1.0, SWITCH_SEC)
	c.set_meta("_slide_tween", tw)


## slide_in を途中で止めて、すべり込む先の位置に戻す。止めずに開き直すと途中の位置が余白に残り、
## 開く・閉じるをくり返すたびにパネルがずれて画面の外へはみ出していた（docs/AUTORUN.md 作業11）
static func stop_slide(c: Control) -> void:
	var tw: Tween = c.get_meta("_slide_tween") if c.has_meta("_slide_tween") else null
	if tw != null and tw.is_valid() and tw.is_running():
		tw.kill()
		c.position = c.get_meta("_slide_end")
		c.modulate.a = 1.0
	c.remove_meta("_slide_tween")


## 画面の切り替え：フェードイン＋わずかに拡大（コンテナの中の子でも位置を崩さない）
static func fade_in(c: Control) -> void:
	c.pivot_offset = c.size * 0.5
	c.modulate.a = 0.0
	c.scale = Vector2(0.985, 0.985)
	var tw := c.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, SWITCH_SEC)
	tw.tween_property(c, "scale", Vector2.ONE, SWITCH_SEC)


## 数字が変わったときに軽く弾ませる
static func bump(c: Control, amount := 1.16) -> void:
	if not c.is_inside_tree() or c.size == Vector2.ZERO:
		# 作ったばかりでまだ大きさが決まっていないときは、決まってから弾ませる
		c.resized.connect(func() -> void: bump(c, amount), CONNECT_ONE_SHOT)
		return
	c.pivot_offset = c.size * 0.5
	var tw := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.scale = Vector2(amount, amount)
	tw.tween_property(c, "scale", Vector2.ONE, BUMP_SEC)


## ラベルの文字を変える。前と違えば弾ませる
static func set_text_bump(label: Label, text: String, amount := 1.16) -> void:
	if label.text == text:
		return
	var had_text := not label.text.is_empty()
	label.text = text
	if had_text:
		bump(label, amount)
