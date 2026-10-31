extends SceneTree
## デバッグ用の開始年と「すぐドラフトへ」の確認（ヘッドレスで約1分）：
##   - タイトル：開始年の初期値は2008年、E/Q（RB/LB）で変わる、2012年以降は DeNA が並ぶ
##   - 2008〜2027年のどの年でも、その年の能力値・日程で開幕日から始まる（12球団・試合あり）
##   - タイトルで2024年・「すぐドラフトへ」を選んで巨人を選ぶ → シーズンを消化して2024年オフのドラフトの段階のハブ
##   - 2025年開始で skip_to_phase(DRAFT) → 春季キャンプ（2026年）へ進める
##   - 2023年開始で skip_to_phase(ACTIVE_DRAFT)、2010年は現役ドラフトが無いのでドラフトの段階で止まる
##
##   godot --headless --path godot --script res://tests/start_year_check.gd -- [スクショの出力先]
##
## 出力先を渡してウィンドウ付きで実行すると、タイトル画面（2024年を選んだところ）のスクショを撮る。
## すべて OK なら "ALL OK"、1つでも NG があれば "FAILED" を出して終了コード 1。

var _out := ""
var _failures := 0
var _gs: Node
var _gd: Node


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_gd = root.get_node("GameData")

	# --- タイトル ---
	change_scene_to_file("res://scenes/title/title.tscn")
	await _frames(6)
	var title := current_scene
	_check("タイトル：開始年の初期値は2008年", title.get("start_year") == 2008, str(title.get("start_year")))
	_check("タイトル：最初の球団にフォーカス", _focus_text() == "読売ジャイアンツ", _focus_text())
	await _key(KEY_E)
	_check("タイトル：E（RB）で2009年", title.get("start_year") == 2009, str(title.get("start_year")))
	await _key(KEY_Q)
	await _key(KEY_Q)
	_check("タイトル：Q（LB）で2008年（下限で止まる）", title.get("start_year") == 2008,
		str(title.get("start_year")))
	title.call("set_start_year", 2012)
	await _frames(3)
	_check("タイトル：2012年は DeNA が並ぶ", _has_button(title, "横浜DeNAベイスターズ")
		and not _has_button(title, "横浜ベイスターズ"), "")
	_check("タイトル：作り直したあとも球団にフォーカス", _focus_text() == "読売ジャイアンツ", _focus_text())
	# 十字キーで下へ進むとデバッグ用の行（開始年のプルダウン）に届く
	var reached := false
	for i in 8:
		await _key(KEY_DOWN)
		if _focused() is OptionButton:
			reached = true
			break
	_check("タイトル：十字キー↓でデバッグ用の開始年に届く", reached, _focus_text())
	title.call("set_start_year", 2024)
	await _frames(3)
	_check("タイトル：見出しが2024年", (title.get_node("%SubLabel") as Label).text.begins_with("2024年"),
		(title.get_node("%SubLabel") as Label).text)
	title.call("set_skip_to_draft", true)
	await _shot("start_year_title")

	# --- 2008〜2027年のどの年でも始められる ---
	for y in range(2008, 2028):
		_gs.new_game("読売ジャイアンツ", y)
		var season: Season = _gs.season
		var teams: Array = _gd.call("teams")
		var ok: bool = _gs.year == y and season != null and teams.size() == 12 \
			and _gs.date_text().begins_with("%d年" % y) and _gs.day == season.first_day()
		var empty := 0
		for t in teams:
			if _gd.call("players_of", t).size() < 40:
				empty += 1
		_check("%d年開始：その年の能力値・日程で開幕日から" % y, ok and empty == 0,
			"%s 球団%d 試合%d 少ない球団%d" % [_gs.date_text(), teams.size(),
				season.games.size() if season != null else 0, empty])

	# --- タイトルから 2024年・すぐドラフトへ ---
	change_scene_to_file("res://scenes/title/title.tscn")
	await _frames(6)
	title = current_scene
	title.call("set_start_year", 2024)
	title.call("set_skip_to_draft", true)
	await _frames(2)
	var button := _find_button(title, "読売ジャイアンツ")
	button.pressed.emit()
	for i in 600:
		await process_frame
		if current_scene != null and current_scene.name == "Hub":
			break
	var season24: Season = _gs.season
	_check("2024年すぐドラフトへ：ハブが開く", current_scene != null and current_scene.name == "Hub",
		str(current_scene.name if current_scene != null else "null"))
	_check("2024年すぐドラフトへ：2024年オフのドラフトの段階", _gs.year == 2024
		and _gs.phase == _gs.Phase.DRAFT and _gs.date_text() == "2024年 オフ",
		"%s %s" % [_gs.date_text(), _gs.phase_name()])
	var played := 0
	for g: Dictionary in season24.games:
		if g["status"] == "played":
			played += 1
	_check("2024年すぐドラフトへ：全試合を消化", season24.played_count() == played and played > 800,
		"%d/%d" % [season24.played_count(), played])
	_check("2024年すぐドラフトへ：自球団の成績が付く", _gs.games_played() >= 140, _gs.record_text())
	var league: RefCounted = _gs.league
	# 新人の入団はドラフト会議が終わってから（ドラフトの段階に入った時点では引退だけ）
	_check("2024年すぐドラフトへ：オフの段階を通った（引退の出来事・ドラフト会議が開いている）",
		not league.call("events", 2024, "retire").is_empty() and _gs.draft_open(),
		"引退%d 新人%d" % [league.call("events", 2024, "retire").size(), league.call("events", 2024, "rookie").size()])
	_check("2024年すぐドラフトへ：可変ボタンはドラフト会議", _gs.button_text() == "ドラフト会議",
		_gs.button_text())

	# --- 2025年開始：すぐドラフトへ → 翌年へ ---
	_gs.new_game("北海道日本ハムファイターズ", 2025)
	var ok25: bool = _gs.skip_to_phase(_gs.Phase.DRAFT)
	_check("2025年開始：ドラフトの段階へ飛べる", ok25 and _gs.year == 2025, _gs.phase_name())
	_gs.advance()
	_check("2025年開始：春季キャンプで2026年", _gs.phase == _gs.Phase.CAMP and _gs.year == 2026
		and _gs.date_text() == "2026年 2月" and _gd.call("players_of", _gs.team).size() >= 50,
		"%s %d人" % [_gs.date_text(), _gd.call("players_of", _gs.team).size()])

	# --- 指定した段階へ飛ぶ ---
	_gs.new_game("阪神タイガース", 2023)
	var ok23: bool = _gs.skip_to_phase(_gs.Phase.ACTIVE_DRAFT)
	_check("2023年開始：現役ドラフトの段階へ飛べる", ok23 and _gs.phase == _gs.Phase.ACTIVE_DRAFT,
		_gs.phase_name())
	var ok_fa: bool = _gs.skip_to_phase(_gs.Phase.FA_TRADE)
	_check("2023年：続けてFAの段階へ飛べる", ok_fa and _gs.fa() != null, _gs.phase_name())
	_gs.new_game("阪神タイガース", 2010)
	var ok10: bool = _gs.skip_to_phase(_gs.Phase.ACTIVE_DRAFT)
	_check("2010年：現役ドラフトは無いのでドラフトの段階で止まる",
		not ok10 and _gs.phase == _gs.Phase.DRAFT and _gs.year == 2010, _gs.phase_name())

	print("ALL OK" if _failures == 0 else "FAILED (%d)" % _failures)
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s %s%s" % ["OK" if ok else "NG", label, "" if detail.is_empty() else "（%s）" % detail])
	if not ok:
		_failures += 1


func _focused() -> Control:
	return root.gui_get_focus_owner()


func _focus_text() -> String:
	var c := _focused()
	if c is Button:
		return (c as Button).text
	return str(c)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _has_button(node: Node, text: String) -> bool:
	return _find_button(node, text) != null


func _key(keycode: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		Input.parse_input_event(e)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String, wait := 0.4) -> void:
	if _out.is_empty() or DisplayServer.get_name() == "headless":
		return
	await create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(name + ".png"))
