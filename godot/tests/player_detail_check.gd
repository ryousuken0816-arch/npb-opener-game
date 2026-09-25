extends SceneTree
## 選手詳細（PlayerDetail）の確認。キーボード（矢印・Enter・Esc・Q/E）とマウスの両方で：
##   采配の一覧の名前札 → 開く・タブ切り替え・前後の選手・閉じる（フォーカスが札に戻る）
##   マウスで札をクリック／右クリック → 開く、タブ・▲▼・閉じるをクリック
##   投手1軍登録・起用設定：札を選んでもう一度 Enter／クリックで開く、Esc はまず選択の取り消し
##   選手一覧：行で Enter／クリックで開く、前後の選手は一覧の並び
##   日付を進めると今季成績が増える（開いたまま・開き直し）
##   全球団の全選手で4つのタブを表示してエラーが出ない（2008年・2026年）
## を調べる。xvfb-run で実行するとスクリーンショットも保存する。
##
##   xvfb-run godot --path godot --resolution 1280x720 \
##       --script res://tests/player_detail_check.gd -- <出力先>
##
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。
## （このスクリプトはオートロードより先にコンパイルされるので、PlayerDetail などのクラス名は型に使わない）

const DETAIL_SCRIPT := "res://scenes/player_detail/player_detail.gd"

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
	game_state.new_game("阪神タイガース")
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	var hub := current_scene

	# --- 采配の一覧（キーボード）---
	await _key(KEY_DOWN)
	await _key(KEY_DOWN)
	await _key(KEY_ENTER)
	var tactics: Node = hub.get_node("%TacticsView")
	_check("采配を開く", hub.get("_open_key") == "tactics", str(hub.get("_open_key")))
	for i in 3:
		if _is_tag(_focused()):
			break
		await _key(KEY_RIGHT)
	var tag := _focused()
	_check("一覧：→で名前札にフォーカス", _is_tag(tag), _describe(tag))
	await _key(KEY_ENTER)
	var detail := _detail()
	_check("一覧：Enter で選手詳細を開く", detail != null and detail.get("player_id") == tag.get("player_id"),
		str(detail.get("player_id")) if detail != null else "なし")
	if detail == null:
		_finish()
		return
	await _shot("d1_summary_keyboard")
	await _key(KEY_E)
	_check("E（RB）で成績タブ", detail.get("tab") == 1, str(detail.get("tab")))
	await _shot("d2_stats")
	await _key(KEY_E)
	_check("E で経歴タブ", detail.get("tab") == 2, str(detail.get("tab")))
	await _shot("d3_career")
	await _key(KEY_E)
	_check("E で契約タブ", detail.get("tab") == 3, str(detail.get("tab")))
	await _shot("d4_contract")
	await _key(KEY_E)
	_check("E で概要タブへ回る", detail.get("tab") == 0, str(detail.get("tab")))
	await _key(KEY_Q)
	_check("Q（LB）で前のタブ（契約）", detail.get("tab") == 3, str(detail.get("tab")))
	await _key(KEY_Q)
	await _key(KEY_Q)
	await _key(KEY_Q)
	var ids: Array = detail.get("_ids")
	var first_id: String = detail.get("player_id")
	var at := ids.find(first_id)
	await _key(KEY_DOWN)
	_check("↓で次の選手", detail.get("player_id") == ids[(at + 1) % ids.size()],
		str(detail.get("player_id")))
	await _shot("d5_next_player")
	await _key(KEY_RIGHT)
	_check("→でもう1人次", detail.get("player_id") == ids[(at + 2) % ids.size()], "")
	await _key(KEY_LEFT)
	await _key(KEY_UP)
	_check("←↑で元の選手", detail.get("player_id") == first_id, str(detail.get("player_id")))
	_check("一覧の並びで送る（札の数と同じ）", ids.size() == game_state.my_team().players.size(),
		"%d / %d" % [ids.size(), game_state.my_team().players.size()])
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check("Esc で閉じる", _detail() == null, "")
	_check("閉じたら札にフォーカスが戻る", _focused() == tag, _describe(_focused()))
	_check("Esc は下の画面に届かない（采配は開いたまま）",
		hub.get("_open_key") == "tactics" and tactics.get("_page") == "", str(tactics.get("_page")))

	# --- 采配の一覧（マウス）---
	var tags := _tags(tactics.get("_home"))
	var tag2: Control = tags[5]
	await _click(tag2)
	detail = _detail()
	_check("クリックで選手詳細を開く", detail != null and detail.get("player_id") == tag2.get("player_id"), "")
	await _click(_button(detail, "経歴"))
	_check("タブをクリック（経歴）", detail.get("tab") == 2, str(detail.get("tab")))
	var before: String = detail.get("player_id")
	await _click(_button(detail, "次 ▼"))
	_check("「次 ▼」クリックで次の選手", detail.get("player_id") != before, "")
	await _click(_button(detail, "▲ 前"))
	_check("「▲ 前」クリックで戻る", detail.get("player_id") == before, "")
	await _click(_button(detail, "✕ 閉じる"))
	await _frames(2)
	_check("「閉じる」クリックで閉じる", _detail() == null, "")
	await _click(tags[8], MOUSE_BUTTON_RIGHT)
	detail = _detail()
	_check("右クリックでも開く", detail != null and detail.get("player_id") == tags[8].get("player_id"), "")
	await _key(KEY_ESCAPE)

	# --- 投手1軍登録（キーボード・マウス）---
	await _key(KEY_E)
	_check("E で投手1軍登録", tactics.get("_page") == "pitchers", str(tactics.get("_page")))
	await _frames(3)
	var pitchers: Node = tactics.get("_register_pitchers")
	var tag_id := str(_focused().get("player_id")) if _is_tag(_focused()) else ""
	await _key(KEY_ENTER)
	_check("1軍登録：Enter で札を選ぶ（詳細はまだ）", pitchers.get("_selected") != null and _detail() == null, "")
	await _key(KEY_ENTER)
	detail = _detail()
	_check("1軍登録：もう一度 Enter で選手詳細", detail != null and detail.get("player_id") == tag_id,
		tag_id)
	await _shot("d6_register_pitcher")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check("1軍登録：閉じても選択はそのまま", _detail() == null and pitchers.get("_selected") != null, "")
	await _key(KEY_ESCAPE)
	_check("1軍登録：Esc で選択を取り消す（画面はそのまま）",
		pitchers.get("_selected") == null and tactics.get("_page") == "pitchers",
		str(tactics.get("_page")))
	var farm_tags := _tags(pitchers.get("_farm_box"))
	# 札を選ぶと作り直されるので、同じ位置をもう一度クリックする
	var farm_id := str(farm_tags[0].get("player_id"))
	var farm_pos: Vector2 = farm_tags[0].get_global_rect().get_center()
	await _click_at(farm_pos)
	_check("1軍登録：クリックで札を選ぶ", pitchers.get("_selected") != null and _detail() == null, "")
	await _click_at(farm_pos)
	detail = _detail()
	_check("1軍登録：同じ札をもう一度クリックで選手詳細", detail != null
		and detail.get("player_id") == farm_id, farm_id)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)

	# --- 起用設定 ---
	await _key(KEY_E)
	await _key(KEY_E)
	_check("E E で起用設定", tactics.get("_page") == "order", str(tactics.get("_page")))
	await _frames(3)
	var order: Node = tactics.get("_order")
	tag_id = str(_focused().get("player_id")) if _is_tag(_focused()) else ""
	await _key(KEY_ENTER)
	await _key(KEY_ENTER)
	detail = _detail()
	_check("起用設定：スタメンの札で Enter 2回で選手詳細",
		detail != null and not tag_id.is_empty() and detail.get("player_id") == tag_id, tag_id)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)
	_check("起用設定：Esc で選択を取り消す", order.get("_sel_index") == -1 and tactics.get("_page") == "order", "")
	var bench_tags := _tags(order.get("_bench_grid"))
	var bench_id := str(bench_tags[0].get("player_id"))
	var bench_pos: Vector2 = bench_tags[0].get_global_rect().get_center()
	await _click_at(bench_pos)
	await _click_at(bench_pos)
	detail = _detail()
	_check("起用設定：控えの札を2回クリックで選手詳細", detail != null
		and detail.get("player_id") == bench_id, bench_id)
	await _key(KEY_ESCAPE)
	await _key(KEY_ESCAPE)

	# --- 選手一覧 ---
	await _key(KEY_E)
	await _key(KEY_E)
	_check("E E で選手一覧", tactics.get("_page") == "list", str(tactics.get("_page")))
	await _frames(3)
	var tree := _focused() as Tree
	_check("選手一覧：一覧にフォーカス", tree != null, _describe(_focused()))
	await _key(KEY_DOWN)
	var row_id := str(tree.get_selected().get_metadata(0))
	await _key(KEY_ENTER)
	detail = _detail()
	_check("選手一覧：Enter で選んだ行の選手詳細", detail != null and detail.get("player_id") == row_id, row_id)
	await _key(KEY_DOWN)
	var next_row := tree.get_selected().get_next()
	_check("選手一覧：↓で一覧の次の行の選手", next_row != null
		and detail.get("player_id") == str(next_row.get_metadata(0)), "")
	await _key(KEY_ESCAPE)
	await _frames(2)
	_check("選手一覧：閉じたら一覧にフォーカス", _focused() == tree, _describe(_focused()))
	var item := tree.get_root().get_child(4)
	var rect := tree.get_item_area_rect(item)
	await _click_at(tree.get_global_transform() * (rect.get_center() + Vector2(0, 0)))
	detail = _detail()
	_check("選手一覧：行のクリックで選手詳細", detail != null
		and detail.get("player_id") == str(item.get_metadata(0)), str(item.get_metadata(0)))
	await _key(KEY_ESCAPE)
	# 投手のタブ（E）→ 投手の詳細
	await _key(KEY_E)
	tree = _focused() as Tree
	await _key(KEY_ENTER)
	detail = _detail()
	_check("選手一覧（投手）：Enter で投手の選手詳細", detail != null and bool(
		root.get_node("GameData").player(detail.get("player_id")).get("is_pitcher")), "")
	await _shot("d7_pitcher_summary")
	await _key(KEY_E)
	await _shot("d8_pitcher_stats")
	await _key(KEY_ESCAPE)

	# --- 日付を進めると今季成績が増える ---
	var team: SimTeam = game_state.my_team()
	# セ・リーグの球団なので DHなしの4番（2008年の阪神の開幕は3月28日）
	var batter: SimPlayer = team.lineup(false)[3][0]
	var pitcher: SimPlayer = team.rotation[0]
	var detail_script: Script = load(DETAIL_SCRIPT)
	detail = detail_script.call("open", hub, batter.id)
	await _frames(2)
	var text_before := _season_text(detail)
	_check("開幕前は出場なし", text_before.begins_with("出場なし"), text_before)
	game_state.start_fast_forward(game_state.day + 12)
	while game_state.is_fast_forwarding():
		await process_frame
	await _frames(2)
	var text_after := _season_text(detail)
	var pa := int(game_state.season.batting.get(batter.id, {}).get("pa", 0))
	_check("開いたまま日付を進めると今季成績が増える", pa > 0 and text_after != text_before
		and text_after.begins_with("打率"), "%s → %s（%d打席）" % [text_before, text_after, pa])
	detail.call("show_tab", 1)
	await _frames(2)
	_check("成績タブに今季の行", _label_exists(detail, "%d打席" % pa) or _cell_exists(detail, str(pa)), "")
	await _shot("d9_stats_after_week")
	detail.call("close")
	await _frames(2)
	game_state.start_fast_forward(game_state.day + 20)
	while game_state.is_fast_forwarding():
		await process_frame
	detail = detail_script.call("open", hub, batter.id)
	await _frames(2)
	var pa2 := int(game_state.season.batting.get(batter.id, {}).get("pa", 0))
	_check("開き直しても増えた今季成績", pa2 > pa and _season_text(detail) != text_after,
		"%s（%d打席）" % [_season_text(detail), pa2])
	await _shot("d10_summary_after_month")
	detail.call("close")
	detail = detail_script.call("open", hub, pitcher.id)
	await _frames(2)
	var g := int(game_state.season.pitching.get(pitcher.id, {}).get("g", 0))
	_check("先発投手にも今季の登板", g > 0 and _season_text(detail).begins_with("防"), _season_text(detail))
	await _shot("d11_pitcher_after_month")
	detail.call("close")

	# --- 他球団の選手（同じ情報量）---
	var game_data: Node = root.get_node("GameData")
	var other_id := ""
	for p: Dictionary in game_data.players_of("読売ジャイアンツ"):
		if p["name"] == "阿部 慎之助":
			other_id = p["id"]
	detail = detail_script.call("open", hub, other_id)
	await _frames(2)
	_check("他球団の選手も開ける（登録状況も出る）", detail != null and _label_exists(detail, "1軍・スタメン"), "")
	await _shot("d12_other_team")
	detail.call("show_tab", 1)
	await _shot("d13_other_team_stats")
	detail.call("show_tab", 2)
	await _shot("d14_other_team_career")
	detail.call("close")

	# --- 全選手で全タブ（エラーが出ないこと）---
	var count := await _render_all(detail_script, hub, game_data)
	_check("2008年：全選手の4タブを表示", count == game_data.ratings["players"].size(), "%d人" % count)
	game_state.new_game("阪神タイガース", 2026)
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await _frames(6)
	hub = current_scene
	count = await _render_all(detail_script, hub, game_data)
	_check("2026年（日程なし）：全選手の4タブを表示", count == game_data.ratings["players"].size(), "%d人" % count)
	var numbered := ""
	for p: Dictionary in game_data.players_of("阪神タイガース"):
		if not str(game_data.uniform_numbers(2026).get(p["id"], "")).is_empty():
			numbered = p["id"]
			break
	detail = detail_script.call("open", hub, numbered)
	await _frames(2)
	_check("2026年：背番号を表示", _label_exists(detail, str(game_data.uniform_numbers(2026)[numbered])), "")
	await _shot("d15_2026_number")
	detail.call("show_tab", 2)
	await _shot("d16_2026_career")
	detail.call("close")
	_finish()


func _finish() -> void:
	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(0 if _failures == 0 else 1)


## 全球団の全選手を順に開き、4つのタブを表示する（表示できた人数）
func _render_all(detail_script: Script, hub: Node, game_data: Node) -> int:
	var count := 0
	for team: String in game_data.teams():
		var ids: Array = detail_script.call("team_order", team)
		var detail: Node = detail_script.call("open", hub, ids[0], ids)
		await _frames(1)
		for i in ids.size():
			for t in 4:
				detail.call("show_tab", t)
			count += 1
			detail.call("step", 1)
		detail.call("close")
		await _frames(1)
	return count


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s %s%s" % ["OK" if ok else "NG", label, "" if detail.is_empty() else "（%s）" % detail])
	if not ok:
		_failures += 1


## 開いている選手詳細（なければ null）
func _detail() -> Node:
	for layer in current_scene.get_children():
		if layer is CanvasLayer:
			for child in layer.get_children():
				if child.has_method("step") and not child.is_queued_for_deletion():
					return child
	return null


func _season_text(detail: Node) -> String:
	var label := detail.find_child("SeasonMain", true, false) as Label
	return label.text if label != null else ""


func _label_exists(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).text.contains(text):
			return true
	return false


func _cell_exists(node: Node, text: String) -> bool:
	for label in node.find_children("*", "Label", true, false):
		if (label as Label).text == text:
			return true
	return false


func _button(node: Node, text: String) -> Control:
	for b in node.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b
	return null


## node 以下の名前札（選手の札のみ、木の順）
func _tags(node: Node) -> Array:
	var result: Array = []
	for c in node.find_children("*", "Button", true, false):
		if _is_tag(c) and not str(c.get("player_id")).is_empty() and (c as Control).is_visible_in_tree():
			result.append(c)
	return result


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _describe(c: Control) -> String:
	return "なし" if c == null else "%s %s" % [c.get_class(), c.name]


func _is_tag(c: Control) -> bool:
	return c != null and c.has_method("setup_player")


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func _click(c: Control, button := MOUSE_BUTTON_LEFT) -> void:
	if c == null:
		_check("クリックする項目がある", false, "")
		return
	await _click_at(c.get_global_rect().get_center(), button)


func _click_at(pos: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	Input.parse_input_event(motion)
	await _frames(1)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT and pressed else 0
		e.position = pos
		e.global_position = pos
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.3) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	if wait > 0.0:
		await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
