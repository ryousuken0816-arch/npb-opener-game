extends SceneTree
## コントローラー操作の確認（docs/references/README.md「コントローラー操作」）。マウスを使わず、
## キーボードの矢印・Enter・Esc・E（＝RB）だけで：
##   球団選択 → ハブ → 日程表で日付を選んで早送り → Esc（Ⓑ）で早送り中止 → 戻る
##   → 采配 → 投手1軍登録で2軍の投手と1軍の投手を入れ替え → 戻る → 戻る（ハブ）
## が一通りできることを調べる。各段階のスクリーンショットも保存する（xvfb-run で実行したとき）。
##
##   xvfb-run godot --path godot --resolution 1280x720 \
##       --script res://tests/pad_flow_check.gd -- <出力先>
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

var _out := ""
var _failures := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var game_state: Node = root.get_node("GameState")
	var ui_input: Node = root.get_node("UiInput")

	# --- 球団選択 ---
	change_scene_to_file("res://scenes/title/title.tscn")
	await _frames(6)
	_check("タイトル：最初の球団にフォーカス", _focus_text() == "読売ジャイアンツ", _focus_text())
	await _key(KEY_DOWN)
	_check("タイトル：↓で次の球団", _focus_text() == "阪神タイガース", _focus_text())

	# --- コントローラーの押しっぱなしで連続移動（十字キー・左スティック） ---
	var title := current_scene
	var start := int(ui_input.call("focus_index", title))
	await _joy_button(JOY_BUTTON_DPAD_DOWN, true)
	await _frames(2)
	_check("十字キー↓：押した瞬間は1つ", int(ui_input.call("focus_index", title)) == start + 1,
		"%d→%d" % [start, ui_input.call("focus_index", title)])
	await create_timer(0.65, true, false, true).timeout
	await _joy_button(JOY_BUTTON_DPAD_DOWN, false)
	var after_hold := int(ui_input.call("focus_index", title))
	_check("十字キー↓：押しっぱなしで複数個動く", after_hold >= start + 3,
		"%d→%d" % [start, after_hold])
	await create_timer(0.3, true, false, true).timeout
	_check("十字キー↓：離したら止まる", int(ui_input.call("focus_index", title)) == after_hold, "")
	await _joy_axis(JOY_AXIS_LEFT_Y, 0.3)
	await create_timer(0.6, true, false, true).timeout
	_check("左スティック：小さな傾きでは動かない", int(ui_input.call("focus_index", title)) == after_hold, "")
	await _joy_axis(JOY_AXIS_LEFT_Y, -0.9)
	await create_timer(0.65, true, false, true).timeout
	await _joy_axis(JOY_AXIS_LEFT_Y, 0.0)
	var after_stick := int(ui_input.call("focus_index", title))
	_check("左スティック↑：倒し続けて複数個動く", after_stick <= after_hold - 3,
		"%d→%d" % [after_hold, after_stick])
	for i in 15:
		if _focus_text() == "阪神タイガース":
			break
		await _key(KEY_UP if int(ui_input.call("focus_index", title)) > start else KEY_DOWN)
	_check("キーボードで阪神に戻る", _focus_text() == "阪神タイガース", _focus_text())
	await _shot("p1_title")
	await _key(KEY_ENTER)
	await _frames(6)
	var hub := current_scene
	_check("Enter で球団決定→ハブ", game_state.team == "阪神タイガース" and hub.name == "Hub",
		"%s / %s" % [game_state.team, hub.name])

	# --- ハブ → 日程表 ---
	_check("ハブ：試合へにフォーカス", _menu_key() == "advance", _menu_key())
	await _key(KEY_DOWN)
	_check("ハブ：↓で日程表", _menu_key() == "schedule", _menu_key())
	var page_before: int = hub.get_node("%Standings").get("_page")
	await _key(KEY_E)
	_check("ハブ：E（RB）で順位表のリーグ切り替え",
		hub.get_node("%Standings").get("_page") != page_before, "")
	await _shot("p2_hub")
	await _key(KEY_ENTER)
	_check("Enter で日程表を開く", hub.get("_open_key") == "schedule", str(hub.get("_open_key")))
	var schedule: Node = hub.get_node("%ScheduleView")
	_check("日程表：1日進めるにフォーカス", _focus_text() == "▶ 1日進める", _focus_text())

	# 日付の列へ（↓）→ さらに↓でスライダーへ、→で10日先の表示に送る → ↑で日付の列に戻り、右端の列を選ぶ
	for i in 4:
		if _focused() != null and _focused().has_meta("day"):
			break
		await _key(KEY_DOWN)
	_check("日程表：↓で日付の列にフォーカス", _focused() != null and _focused().has_meta("day"),
		_describe(_focused()))
	for i in 3:
		if _focused() is HSlider:
			break
		await _key(KEY_DOWN)
	_check("日程表：↓でスライダーへ", _focused() is HSlider, _describe(_focused()))
	for i in 10:
		await _key(KEY_RIGHT)
	await _key(KEY_UP)
	_check("日程表：↑で日付の列に戻る", _focused() != null and _focused().has_meta("day"),
		_describe(_focused()))
	await _key(KEY_RIGHT)
	await _key(KEY_RIGHT)
	var target_day := int(_focused().get_meta("day", -1)) if _focused() != null else -1
	await _key(KEY_ENTER)
	_check("日程表：Enter で日付を選ぶ", schedule.get("_selected_day") == target_day,
		"%s / %d" % [schedule.get("_selected_day"), target_day])
	_check("日程表：選び直しても同じ日の列にフォーカス",
		_focused() != null and int(_focused().get_meta("day", -1)) == target_day, _describe(_focused()))
	await _shot("p3_schedule_selected")
	await _key(KEY_ENTER)
	_check("日程表：もう一度 Enter で早送り開始", game_state.is_fast_forwarding(), "")
	await _frames(4)
	_check("日程表：早送り中は中止ボタンにフォーカス", _focus_text() == "■ 早送り中止", _focus_text())
	await _shot("p4_fast_forward", 0.1)
	await _key(KEY_ESCAPE)
	_check("日程表：Esc（Ⓑ）で早送り中止、画面は開いたまま",
		not game_state.is_fast_forwarding() and hub.get("_open_key") == "schedule", "")
	await _frames(3)
	_check("日程表：中止後は元の項目へフォーカス", _focused() != null and schedule.is_ancestor_of(_focused())
		and _focus_text() != "■ 早送り中止", _describe(_focused()))
	await _key(KEY_ESCAPE)
	_check("日程表：Esc で閉じる", hub.get("_open_key") == "", str(hub.get("_open_key")))
	_check("閉じたら日程表のメニューにフォーカス", _menu_key() == "schedule", _menu_key())

	# --- 采配 → 投手1軍登録で入れ替え ---
	await _key(KEY_DOWN)
	_check("ハブ：↓で采配", _menu_key() == "tactics", _menu_key())
	await _key(KEY_ENTER)
	_check("Enter で采配を開く", hub.get("_open_key") == "tactics", "")
	_check("采配：投手1軍登録にフォーカス", _focus_text() == "投手1軍登録", _focus_text())
	await _shot("p5_tactics")
	await _key(KEY_ENTER)
	await _frames(3)
	var tactics: Node = hub.get_node("%TacticsView")
	var pitchers: Node = tactics.get("_register_pitchers")
	_check("Enter で投手1軍登録を開く", tactics.get("_page") == "pitchers", str(tactics.get("_page")))
	var active_box: Node = pitchers.get("_active_box")
	var farm_box: Node = pitchers.get("_farm_box")
	_check("投手1軍登録：1軍の最初の札にフォーカス", _is_tag(_focused())
		and active_box.is_ancestor_of(_focused()), _describe(_focused()))
	await create_timer(0.6).timeout
	_check("フォーカスした札のツールチップを表示", ui_input.get("_tip_panel").visible, "")
	# → で2軍の札へ
	for i in 6:
		if _focused() != null and farm_box.is_ancestor_of(_focused()):
			break
		await _key(KEY_RIGHT)
	_check("投手1軍登録：→で2軍の札へ", _focused() != null and farm_box.is_ancestor_of(_focused()),
		_describe(_focused()))
	await _key(KEY_ENTER)
	var chosen: SimPlayer = pitchers.get("_selected")
	_check("Enter で2軍の投手を選ぶ", chosen != null, "")
	# ← で1軍の札（先発ローテ）へ戻って Enter で入れ替え
	for i in 6:
		if _focused() != null and active_box.is_ancestor_of(_focused()) \
				and not _focused().get("empty_slot"):
			break
		await _key(KEY_LEFT)
	var focus_before := int(root.get_node("UiInput").call("focus_index", active_box))
	await _shot("p6_register_selected")
	await _key(KEY_ENTER)
	var team: SimTeam = game_state.my_team()
	_check("Enter で1軍の投手と入れ替え", chosen != null and team.is_active(chosen),
		str(pitchers.get("_message")))
	_check("入れ替えたあともフォーカスは同じ位置",
		int(root.get_node("UiInput").call("focus_index", active_box)) == focus_before,
		"%d" % focus_before)
	await _shot("p7_register_swapped")
	# E（RB）で次のサブ画面
	await _key(KEY_E)
	_check("采配：E（RB）で次のサブ画面", tactics.get("_page") == "fielders", str(tactics.get("_page")))
	await _key(KEY_Q)
	_check("采配：Q（LB）で前のサブ画面", tactics.get("_page") == "pitchers", str(tactics.get("_page")))
	await _key(KEY_ESCAPE)
	_check("Esc で采配の一覧へ", tactics.get("_page") == "" and hub.get("_open_key") == "tactics", "")
	_check("一覧に戻ったら投手1軍登録にフォーカス", _focus_text() == "投手1軍登録", _focus_text())
	await _key(KEY_ESCAPE)
	_check("Esc でハブへ", hub.get("_open_key") == "", "")
	_check("ハブ：采配のメニューにフォーカス", _menu_key() == "tactics", _menu_key())
	await _shot("p8_hub_back")

	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s %s%s" % ["OK" if ok else "NG", label, "" if detail.is_empty() else "（%s）" % detail])
	if not ok:
		_failures += 1


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focus_text() -> String:
	var c := _focused()
	if _is_tag(c):
		return c.get("tag_text")
	if c is Button:
		return (c as Button).text
	return _describe(c)


func _describe(c: Control) -> String:
	return "なし" if c == null else "%s %s" % [c.get_class(), c.name]


## 名前札（NameTag）か。このスクリプトはオートロードより先にコンパイルされるので、
## UiTheme（GameData を使う）に依存するクラス名はここでは使わない
func _is_tag(c: Control) -> bool:
	return c != null and c.has_method("setup_player")


## ハブのメニューでフォーカスしているボタンのキー（HubMenuButton.key）
func _menu_key() -> String:
	var c := _focused()
	if c != null and c.get_parent() != null and c.get_parent().has_signal("chosen"):
		return c.get_parent().get("key")
	return _describe(c)


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func _joy_button(button: JoyButton, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)
	await _frames(2)


func _joy_axis(axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## 画面の切り替えの演出（0.2秒以内）が終わるのを待ってから撮る
func _shot(name: String, wait := 0.3) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	if wait > 0.0:
		await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
