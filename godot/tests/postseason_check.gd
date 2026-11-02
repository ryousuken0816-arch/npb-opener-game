extends SceneTree
## CS・日本シリーズの確認（docs/AUTORUN.md 作業23）。ヘッドレス可（約1分）。ウィンドウ付きで出力先を渡すとスクショも保存。
## 1) 2008年（巨人）：公式戦の最終日のあとポストシーズンへ。組み合わせ（2位対3位・1位にアドバンテージ）・日程（最終日より後、
##    史実に近い間隔）・球場（主催球団の本拠地）、ハブの可変ボタン→ポストシーズンの画面→「次の試合へ」で日付が追従、
##    「この段階を最後まで」（1日ずつ早送り）。途中でセーブ→そのまま日本一まで→ロードして日本一まで＝同じ結果。
##    公式戦の成績はポストシーズンで変わらない。日本一の演出が出る。歴代に残り、「表彰へ」で表彰→FAへ進める
## 2) 2020年：セはCSなし（優勝球団がそのまま日本シリーズ）、パは1位と2位の4試合・3勝。自球団が出ない年は一気に進められる
## 3) 優勝争い：マジックの点灯と優勝の決定が1回ずつ記録される
##
##   godot --headless --path godot --script res://tests/postseason_check.gd -- [出力先]

var _out := ""
var _failures := 0
var _gs: Node
var _sg: GDScript


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ""
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	_run.call_deferred()


func _run() -> void:
	_gs = root.get_node("GameState")
	_sg = load("res://scripts/save_game.gd")
	_sg.set("dir", _sg.call("test_dir"))
	_sg.set("autosave_enabled", false)
	await _check_2008()
	_check_2020()
	for slot: String in _sg.call("all_slots"):
		_sg.call("delete", slot)
	print("\n== 結果: %s ==" % ("ALL OK" if _failures == 0 else "FAILED（%d件）" % _failures))
	quit(1 if _failures > 0 else 0)


func _check_2008() -> void:
	print("\n-- 1) 2008年（巨人）--")
	_gs.new_game("読売ジャイアンツ", 2008)
	var season: Object = _gs.season
	_gs.advance_through(season.last_day(), true)
	_check(_gs.phase == _gs.Phase.POSTSEASON, "最終日のあとポストシーズンへ（%s %s）" % [_gs.phase_name(), _gs.date_text()])
	var race: Dictionary = _gs.pennant_race
	for lg: String in ["C", "P"]:
		var st: Dictionary = race.get(lg, {})
		_check(st.has("clinched") and st.get("team", "") == _gs.standings(lg)[0]["team"],
			"%s 優勝決定 %s %s（マジック点灯 %s %s）" % [lg, st.get("clinched", "-"), st.get("team", "-"),
				st.get("magic", "-"), st.get("magic_date", "-")])
	var ps: Object = _gs.postseason
	var regular := _regular_snapshot()
	var c_order: Array = ps.order["C"]
	var c1: Dictionary = ps.get_series("C1")
	var c2: Dictionary = ps.get_series("C2")
	var js: Dictionary = ps.get_series("JS")
	_check(c1["high"] == c_order[1] and c1["low"] == c_order[2] and c1["need"] == 2 and c1["games"].size() == 3,
		"セCS1st：2位%s 対 3位%s、3試合・2勝" % [c1["high"], c1["low"]])
	_check(c2["high"] == c_order[0] and c2["adv"] == 1 and c2["need"] == 4 and c2["games"].size() == 6,
		"セCSファイナル：1位%s にアドバンテージ1勝、6試合・4勝" % c2["high"])
	_check(js["games"].size() == 7 and js["need"] == 4, "日本シリーズ 7試合・4勝")
	_check(c1["games"][0]["day"] > season.last_day() and c1["games"][0]["venue"] != ""
		and c2["games"][0]["day"] > c1["games"][-1]["day"] and js["games"][0]["day"] > c2["games"][-1]["day"],
		"日程：%s CS1st（%s）→ %s ファイナル → %s 日本シリーズ" % [c1["games"][0]["date"], c1["games"][0]["venue"],
			c2["games"][0]["date"], js["games"][0]["date"]])
	_check(_gs.event_text() == "クライマックスシリーズ" and _gs.button_text() == "試合へ",
		"見出し：%s／可変ボタン：%s" % [_gs.event_text(), _gs.button_text()])

	# ハブ：可変ボタン → ポストシーズンの画面 → 次の試合へ（日付が追従）
	change_scene_to_file("res://scenes/hub/hub.tscn")
	await process_frame
	await process_frame
	var hub: Node = current_scene
	hub.call("_on_menu_chosen", "advance")
	await process_frame
	_check(hub.get("_open_key") == "postseason", "可変ボタンでポストシーズンの画面を開く")
	var view: Node = hub.get("_postseason_view")
	var day0: int = _gs.day
	var date0: String = _gs.date_text()
	(view.get("_day_button") as Button).pressed.emit()
	await _wait_fast_forward()
	_check(_gs.day > day0 and _gs.date_text() != date0 and hub.get_node("%MonthLabel").text == _gs.month_text(),
		"次の試合へ：%s → %s（ハブの日付 %s）" % [date0, _gs.date_text(), hub.get_node("%MonthLabel").text])
	_check(not c1["games"][0]["result"].is_empty() and _gs.season.played_count() == regular["played"],
		"CS1st 第1戦 %s（公式戦の試合数は変わらない）" % _score(c1["games"][0]))
	(view.get("_round_button") as Button).pressed.emit()
	await _wait_fast_forward()
	_check(not c1["winner"].is_empty() and not ps.get_series("P1")["winner"].is_empty(),
		"この段階を最後まで：セ %s（%s）、パ %s → %s" % [c1["winner"], ps.score_text(c1),
			ps.get_series("P1")["winner"], _gs.date_text()])
	_check(c2["low"] == c1["winner"], "ファイナルの相手＝ファーストの勝者（%s）" % c2["low"])
	if _out != "":
		await _shot("postseason_cs.png")

	# 途中でセーブ → そのまま日本一まで → ロードして日本一まで
	var error: String = _sg.call("save", "slot1")
	_check(error.is_empty(), "ファイナルの前にセーブ %s" % error)
	_gs.postseason_play_all()
	var champ1: String = ps.champion
	var js_text: String = ps.score_text(js)
	_check(not champ1.is_empty() and js["winner"] == champ1 and ps.wins_of(js, champ1) == 4,
		"日本一：%s（%s、対 %s）" % [champ1, js_text, js["loser"]])
	for s: Dictionary in ps.series:
		var hw: int = ps.wins_of(s, s["high"])
		var lw: int = ps.wins_of(s, s["low"])
		var ok: bool = s["winner"] != "" and (maxi(hw, lw) >= s["need"] or s["games"].size() == s["max_games"])
		_check(ok, "%s：%s %d−%d %s → %s（%d試合）" % [s["name"], s["high"], hw, lw, s["low"], s["winner"],
			s["games"].size()])
	_check(_gs.button_text() == "表彰へ" and _gs.event_text() == "日本一決定",
		"日本一のあと：%s／%s" % [_gs.button_text(), _gs.event_text()])
	await process_frame
	var fx := _find_celebration(hub)
	_check(fx != null, "日本一の演出が出る")
	if _out != "" and fx != null:
		await _shot("postseason_champion.png")
	if fx != null:
		fx.call("close")
	var regular2 := _regular_snapshot()
	_check(JSON.stringify(regular) == JSON.stringify(regular2), "公式戦の成績・勝敗はポストシーズンで変わらない")
	_check(_gs.postseason_history.has("2008") and _gs.postseason_history["2008"]["champion"] == champ1,
		"歴代に残る：%s" % JSON.stringify(_gs.postseason_history.get("2008", {}).get("series", []).map(
			func(x: Dictionary) -> String: return "%s %s %s" % [x["name"], x["winner"], x["score"]])))
	error = _sg.call("load_slot", "slot1")
	_check(error.is_empty() and _gs.phase == _gs.Phase.POSTSEASON, "ロード（%s %s）%s" % [_gs.phase_name(),
		_gs.date_text(), error])
	_gs.postseason_play_all()
	_check(_gs.postseason.champion == champ1 and _gs.postseason.score_text(_gs.postseason.get_series("JS")) == js_text,
		"ロード後も同じ日本一：%s %s" % [_gs.postseason.champion, js_text])
	# 表彰 → FA へ
	_gs.advance()
	_check(_gs.phase == _gs.Phase.AWARDS and _gs.date_text() == "2008年 オフ", "表彰へ（%s）" % _gs.date_text())
	var guard := 0
	while _gs.phase != _gs.Phase.FA_TRADE and guard < 5:
		_gs.advance()
		guard += 1
	_check(_gs.phase == _gs.Phase.FA_TRADE, "そのあと FA へ（%s）" % _gs.phase_name())
	_gs.new_game("読売ジャイアンツ", 2008)
	change_scene_to_file("res://scenes/title/title.tscn")
	await process_frame


func _check_2020() -> void:
	print("\n-- 2) 2020年 --")
	_gs.new_game("阪神タイガース", 2020)
	_gs.advance_through(_gs.season.last_day(), true)
	var ps: Object = _gs.postseason
	_check(_gs.phase == _gs.Phase.POSTSEASON and ps.get_series("C1").is_empty() and ps.get_series("C2").is_empty(),
		"セはCSなし")
	var js: Dictionary = ps.get_series("JS")
	_check(js["high"] == ps.order["C"][0], "セの優勝球団 %s がそのまま日本シリーズ" % js["high"])
	var p2: Dictionary = ps.get_series("P2")
	_check(ps.get_series("P1").is_empty() and p2["high"] == ps.order["P"][0] and p2["low"] == ps.order["P"][1]
		and p2["need"] == 3 and p2["games"].size() == 4 and p2["adv"] == 1,
		"パは1位%s 対 2位%s、4試合・3勝（1位にアドバンテージ）" % [p2["high"], p2["low"]])
	var alive: bool = ps.team_alive("阪神タイガース")
	_gs.advance()
	if not alive:
		_check(_gs.postseason_done(), "自球団が出ない年は試合へで日本一まで一気に（%s）" % ps.champion)
	while not _gs.postseason_done():
		_gs.advance()
	_check(not ps.champion.is_empty() and _gs.postseason_history.has("2020"), "2020年の日本一 %s（%s）" % [
		ps.champion, ps.score_text(js)])
	_gs.advance()
	_check(_gs.phase == _gs.Phase.AWARDS, "表彰へ")


func _regular_snapshot() -> Dictionary:
	var s: Object = _gs.season
	var pa := 0
	for id: String in s.batting:
		pa += int(s.batting[id]["pa"])
	var outs := 0
	for id: String in s.pitching:
		outs += int(s.pitching[id]["outs"])
	return {"played": s.played_count(), "records": s.records.duplicate(true), "pa": pa, "outs": outs, "wins": _gs.wins}


func _score(g: Dictionary) -> String:
	var r: Dictionary = g["result"]
	if r.is_empty():
		return "%s 未試合" % g["date"]
	return "%s %s %d-%d %s（%s）" % [g["date"], g["away"], r["away_score"], r["home_score"], g["home"], g["venue"]]


func _wait_fast_forward() -> void:
	await process_frame
	var guard := 0
	while _gs.is_fast_forwarding() and guard < 2000:
		await process_frame
		guard += 1
	await process_frame


func _find_celebration(node: Node) -> Node:
	for c in node.get_children():
		if c.has_method("setup") and c is CanvasLayer:
			return c
	return null


func _shot(file_name: String) -> void:
	await create_timer(0.4).timeout
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join(file_name))
	print("スクショ: ", _out.path_join(file_name))


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print(("OK  " if ok else "NG  ") + label)
